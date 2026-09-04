# frozen_string_literal: true

# Un Contrato agrupa uno o mas articulos (orders) de un cliente bajo un solo numero de contrato,
# con UN pago semanal combinado, una tabla de amortizacion, y un saldo que baja con cada pago.
class Contract < ApplicationRecord
  belongs_to :user
  has_many :orders, dependent: :nullify
  has_many :reference_pings, dependent: :destroy
  has_many :reference_checks, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :contract_installments, -> { order(:number) }, dependent: :destroy
  has_one_attached :signature # firma electrónica del cliente (imagen)

  STATUSES = %w[active paid cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  # El número de CONTRATO se asigna hasta que el equipo pulsa "Generar contrato
  # y enviar a firma" (assign_contract_number! en generate_document). Antes de
  # eso — incluso ya pagado el inicial — la compra sólo tiene número de PEDIDO.
  validates :contract_number, uniqueness: true, allow_nil: true

  # Número de pedido: identifica la compra desde el checkout (antes del pago).
  def order_ref
    "PED-#{id}"
  end

  # Asigna el número de contrato (al recibir el pago inicial). Idempotente.
  def assign_contract_number!
    return contract_number if contract_number.present?
    num = nil
    loop do
      candidate = "C#{Time.current.strftime('%y%m')}#{SecureRandom.random_number(100000).to_s.rjust(5, '0')}"
      unless Contract.exists?(contract_number: candidate)
        num = candidate
        break
      end
    end
    update_column(:contract_number, num)
    num
  end

  # ----- dinero -----
  def total_paid
    payments.sum(:amount).to_f
  end

  # ¿Ya se recibió el pago inicial (enganche + primera cuota)?
  # Un contrato de contado (status 'paid') cuenta como pagado.
  # Mientras NO esté pagado, el contrato es un intento de compra (CRM): el cliente
  # llegó a la pantalla de pago pero no ha pagado; no aparece en Órdenes ni ve su calendario.
  def initial_paid?
    status == 'paid' || payments.exists?
  end

  # Saldo pendiente del monto financiado (los pagos semanales lo van liquidando).
  def balance
    [(financed_amount.to_f - total_paid).round(2), 0].max
  end

  def paid_off?
    balance <= 0.009
  end

  # ¿El expediente de la compra está COMPLETO? Comprador capturado y las 4
  # referencias (2 MX + 2 US). Con 3 guardadas "para después", sigue incompleto.
  # Aplica a TODAS las compras (también de contado): pago inicial -> comprador y
  # referencias -> verificación -> contrato. Los datos viven en una de las
  # órdenes del grupo (normalmente la primera).
  def datos_complete?
    os = orders.to_a
    return true if os.empty?

    has_buyer = os.any? { |o| o.respond_to?(:buyer) && o.buyer.present? }
    refs = os.map { |o| o.referrals.size }.max.to_i
    has_buyer && refs >= 4
  end

  # Estado de la CUENTA para el cliente (Mi cuenta), en orden del ciclo de vida:
  # pending_initial -> missing_info -> pending_approval -> pending_signature ->
  # pending_delivery -> active -> paid_off.
  def account_status
    return 'returned' if status == 'returned'
    return 'charged_off' if status == 'charged_off'
    return 'pending_initial' unless initial_paid?
    return 'missing_info' unless datos_complete?

    # El pipeline SIEMPRE se recorre completo (también en compras de contado y
    # aunque el estatus interno ya diga "pagado"): aprobación -> firma -> entrega.
    # Nada se marca "liquidado" antes de entregarse.
    os = orders.to_a
    if os.any?
      return 'pending_approval' unless os.all? { |o| o.respond_to?(:admin_approved) && o.admin_approved }
      return 'pending_signature' if respond_to?(:signed_at) && signed_at.blank?
      return 'pending_delivery' unless os.all? { |o| o.respond_to?(:delivered_at) && o.delivered_at.present? }
    end
    return 'paid_off' if status == 'paid' || paid_off?

    'active'
  end

  # ----- estado de amortizacion -----
  def overdue?
    contract_installments.where.not(status: 'paid').where('due_date < ?', Date.current).exists?
  end

  # Monto vencido: suma del saldo de cuotas no pagadas cuya fecha ya paso.
  def past_due_amount
    contract_installments.where.not(status: 'paid').where('due_date < ?', Date.current)
                         .sum { |i| (i.amount.to_f - i.paid_amount.to_f) }.round(2)
  end

  # Proxima fecha de vencimiento pendiente.
  def next_due_date
    contract_installments.where.not(status: 'paid').order(:due_date).first&.due_date
  end

  # Dias de atraso (desde la cuota vencida mas antigua sin pagar).
  def days_past_due
    d = contract_installments.where.not(status: 'paid').where('due_date < ?', Date.current).minimum(:due_date)
    d ? (Date.current - d).to_i : 0
  end

  # current / past_due / paid / cancelled / returned (devuelto) / charged_off (castigado)
  def payment_status
    return 'cancelled' if status == 'cancelled'
    return 'returned' if status == 'returned'
    return 'charged_off' if status == 'charged_off'
    return 'paid' if status == 'paid' || paid_off?
    overdue? ? 'past_due' : 'current'
  end

  # ----- amortizacion -----
  # Genera la tabla semanal: N cuotas, cada una = pago semanal, sumando el monto financiado.
  FREQUENCIES = %w[weekly biweekly monthly].freeze

  def freq
    frequency.presence || 'weekly'
  end

  # Días por periodo para el cálculo de interés (cláusula SÉPTIMA y la
  # Metodología de cálculo: tasa anual FIJA ÷ 360 × días transcurridos).
  PERIOD_DAYS = { 'weekly' => 7, 'biweekly' => 14, 'monthly' => 30 }.freeze

  # Escala pago-semanal → pago-por-periodo (igual que period_payment).
  def period_scale
    case freq
    when 'monthly'  then 4.333
    when 'biweekly' then 2.0
    else                 1.0
    end
  end

  # Tasa del PERIODO (cláusula SÉPTIMA): tasa anual ÷ 360 × días del periodo.
  def periodic_rate
    rate = Product.respond_to?(:interest_rate) ? Product.interest_rate.to_f : 25.0
    (rate / 100.0) * PERIOD_DAYS.fetch(freq, 7) / 360.0
  end

  # Número de CUOTAS del plazo contratado (weeks está en semanas).
  def scheduled_periods
    [(weeks.to_i / period_scale).round, 1].max
  end

  # Cotización AMORTIZADA sobre SALDO INSOLUTO — la matemática del contrato:
  # interés del periodo = saldo × (tasa anual ÷ 360 × días del periodo);
  # pago fijo de anualidad; la ÚLTIMA cuota liquida el saldo exacto. Se simula
  # la tabla con redondeo a centavos para que el total sea el que se cobra.
  def self.amortized_quote(principal:, frequency:, periods:, annual_rate: nil)
    p = principal.to_f.round(2)
    n = [periods.to_i, 1].max
    rate = (annual_rate || (Product.respond_to?(:interest_rate) ? Product.interest_rate : 25.0)).to_f
    days = PERIOD_DAYS.fetch(frequency.to_s, 7)
    i = (rate / 100.0) * days / 360.0
    return { payment: 0.0, last_payment: 0.0, total: 0.0, interest: 0.0, periods: n } if p <= 0
    if i <= 0
      per = (p / n).round(2)
      last = (p - per * (n - 1)).round(2)
      return { payment: per, last_payment: last, total: p, interest: 0.0, periods: n }
    end
    pay = ((p * i) / (1 - (1 + i)**-n)).round(2)
    saldo = p
    total = 0.0
    last = pay
    (1..n).each do |k|
      interes = (saldo * i).round(2)
      if k == n
        last = (saldo + interes).round(2)
        total = (total + last).round(2)
      else
        total = (total + pay).round(2)
        saldo = (saldo - (pay - interes)).round(2)
      end
    end
    { payment: pay, last_payment: last, total: total, interest: (total - p).round(2), periods: n }
  end

  # Pago por periodo = pago semanal escalado a la frecuencia (quincenal x2, mensual x4.333).
  def period_payment
    fin = financed_amount.to_f
    wp = weekly_payment.to_f
    per = case freq
          when 'monthly'  then wp * 4.333
          when 'biweekly' then wp * 2
          else                 wp
          end
    per = fin / [weeks.to_i, 1].max if per <= 0
    [per.round(2), fin].min
  end

  # Numero de cuotas segun el pago por periodo: se mantiene el pago fijo y la ULTIMA cuota
  # liquida el resto del saldo (si el resto es menor a $1 se une a la cuota anterior).
  def schedule_periods_and_amount
    fin = financed_amount.to_f
    per = period_payment
    return [1, fin.round(2)] if per <= 0 || fin <= 0
    n = (fin / per).ceil
    last = (fin - (n - 1) * per).round(2)
    n -= 1 if n > 1 && last < 1.0
    [[n, 1].max, per]
  end

  # Primera fecha de vencimiento alineada: sabado (semanal/quincenal) o dia 1 (mensual),
  # siempre un periodo completo adelante (si el proximo sabado esta demasiado cerca, se corre).
  def self.aligned_first_due(frequency, from = Date.current)
    if frequency.to_s == 'monthly'
      (from >> 1).beginning_of_month
    else
      d = from
      d += 1 until d.saturday?
      d += 7 if (d - from) < 7
      d
    end
  end

  def due_date_for_period(i)
    base = first_due_date || self.class.aligned_first_due(freq, start_date || Date.current)
    case freq
    when 'monthly'  then (base >> (i - 1))
    when 'biweekly' then base + (i - 1) * 14
    else                 base + (i - 1) * 7
    end
  end

  # Pago del primer periodo (primera cuota).
  def first_period_payment
    _n, amt = schedule_periods_and_amount
    amt.round(2)
  end

  # Pago inicial en el checkout = enganche + primer pago del periodo + cuota de procesamiento.
  def initial_payment
    fee = Product.respond_to?(:processing_fee) ? Product.processing_fee : 0.0
    (downpayment.to_f + first_period_payment + fee).round(2)
  end

  # Intereses MORATORIOS acumulados: sobre cada cuota vencida con más de 1 día de atraso,
  # tasa moratoria anual / 360 por día efectivamente transcurrido (cláusula TERCERA).
  def late_fee_amount
    rate = Product.respond_to?(:mora_rate) ? Product.mora_rate : 0.0
    return 0.0 if rate <= 0
    today = Date.current
    total = contract_installments.where.not(status: 'paid').where('due_date < ?', today).sum do |i|
      days = (today - i.due_date).to_i
      next 0.0 if days <= 1 # 1 día de gracia
      remainder = (i.amount.to_f - i.paid_amount.to_f)
      remainder.positive? ? remainder * (rate / 100.0 / 360.0) * days : 0.0
    end
    total.round(2)
  end

  def build_amortization!(start: nil)
    contract_installments.delete_all
    self.first_due_date ||= self.class.aligned_first_due(freq, start_date || Date.current)
    save!(validate: false) if changed?
    # Tabla AMORTIZADA sobre saldo insoluto (cláusula SÉPTIMA). Las columnas
    # financiado/pago se sincronizan con la tabla: lo que se muestra es
    # exactamente lo que se cobra.
    q = self.class.amortized_quote(principal: principal_amount, frequency: freq, periods: scheduled_periods)
    n = q[:periods]
    return if n <= 0 || q[:total] <= 0
    update_columns(financed_amount: q[:total], weekly_payment: (q[:payment] / period_scale).round(2))
    rows = (1..n).map do |i|
      { number: i, due_date: due_date_for_period(i), amount: (i == n ? q[:last_payment] : q[:payment]), paid_amount: 0, status: 'pending' }
    end
    contract_installments.create!(rows)
  end

  # Cargo financiero implícito del modelo: la diferencia del factor a 100.
  # factor 1.25 → 25% sobre el principal financiado.
  def finance_factor
    Product.respond_to?(:finance_factor) ? Product.finance_factor : 1.25
  end

  # Tasa ordinaria anual FIJA del contrato (Seguridad → Tasas e impuestos).
  def interest_rate
    Product.respond_to?(:interest_rate) ? Product.interest_rate.to_f : ((finance_factor - 1) * 100).round(2)
  end

  # Periodos por año según la frecuencia (semanal 52, quincenal 26, mensual 12).
  def periods_per_year
    case freq
    when 'monthly'  then 12
    when 'biweekly' then 26
    else                 52
    end
  end

  # PRINCIPAL del contrato = precio de contado − enganche.
  def principal_amount
    [(total_amount.to_f - downpayment.to_f).round(2), 0].max
  end

  # Monto de INTERÉS = financiado − principal.
  def interest_amount
    [(financed_amount.to_f - principal_amount).round(2), 0].max
  end

  # TASA DE INTERÉS ORDINARIA ANUAL del contrato (simple, SIN seguro):
  # (interés ÷ principal) anualizada por el plazo real. Ej.: $25 sobre $100 a
  # 12 meses = 25% anual; a 3 meses = 100% anual.
  def annual_interest_rate
    p = principal_amount
    return 0.0 if p <= 0
    n = contract_installments.count
    n = [weeks.to_i, 1].max if n.zero?
    years = n.to_f / periods_per_year
    return 0.0 if years <= 0
    ((interest_amount / p) / years * 100).round(1)
  end

  # CAT EFECTIVO del contrato (informativo, metodología Banxico): TIR de los flujos
  # reales anualizada compuesta. Incluye la cuota de procesamiento (costo obligatorio,
  # se paga a la firma) y EXCLUYE el seguro opcional (waiver).
  def computed_cat
    p = principal_amount
    return 0.0 if p <= 0
    fee = Product.respond_to?(:processing_fee) ? Product.processing_fee : 0.0
    disbursed = (p - fee).round(2)
    return 0.0 if disbursed <= 0
    pays = contract_installments.order(:number).pluck(:amount).map(&:to_f)
    if pays.empty?
      n, per = schedule_periods_and_amount
      pays = Array.new(n, per)
    end
    return 0.0 if pays.empty? || pays.sum <= disbursed
    pv = ->(i) { pays.each_with_index.sum { |a, k| a / ((1 + i)**(k + 1)) } }
    lo = 0.0
    hi = 4.0
    60.times do
      mid = (lo + hi) / 2.0
      pv.call(mid) > disbursed ? lo = mid : hi = mid
    end
    i = (lo + hi) / 2.0
    (((1 + i)**periods_per_year - 1) * 100).round(1)
  rescue StandardError
    0.0
  end

  # Pago aplicado a SALDO (saldo insoluto REAL): el excedente — más allá de la
  # cuota próxima pendiente — paga PRINCIPAL directo. El saldo insoluto es el
  # VALOR PRESENTE de las cuotas pendientes a la tasa del contrato (propiedad
  # de toda tabla amortizada); se re-amortiza (saldo − extra) con el MISMO
  # pago: el plazo se ACORTA y los intereses de las cuotas que ya no correrán
  # dejan de causarse solos — cláusulas DÉCIMA CUARTA/QUINTA. (Antes se
  # perdonaba un 25% plano del extra: regalaba de más al inicio del plazo.)
  # (El modo normal/PLAZO usa apply_payment!: el extra adelanta cuotas futuras.)
  def apply_payment_saldo!(amount)
    nxt = contract_installments.where.not(status: 'paid').order(:number).first
    due = nxt ? (nxt.amount.to_f - nxt.paid_amount.to_f).round(2) : 0.0
    cover = [amount.to_f, due].min.round(2)
    extra = (amount.to_f - cover).round(2)

    apply_payment!(cover) if cover.positive?

    if extra.positive?
      i = periodic_rate
      pend = contract_installments.where.not(status: 'paid').order(:number).to_a
      if pend.any?
        rp = pend.each_with_index.sum { |row, k| (row.amount.to_f - row.paid_amount.to_f) / ((1 + i)**(k + 1)) }.round(2)
        new_rp = (rp - extra).round(2)
        start_num = pend.first.number
        first_due = pend.first.due_date || due_date_for_period(start_num)
        contract_installments.where.not(status: 'paid').delete_all
        if new_rp <= 0.009
          update_columns(financed_amount: total_paid, status: (status == 'cancelled' ? status : 'paid'))
        else
          per = [period_payment.to_f, 0.01].max
          rows = []
          saldo = new_rp
          1000.times do |k|
            interes = (saldo * i).round(2)
            due_date = case freq
                       when 'monthly'  then first_due >> k
                       when 'biweekly' then first_due + (k * 14)
                       else                 first_due + (k * 7)
                       end
            if (saldo + interes) <= (per + 0.005)
              rows << { number: start_num + k, due_date: due_date, amount: (saldo + interes).round(2), paid_amount: 0, status: 'pending' }
              break
            end
            rows << { number: start_num + k, due_date: due_date, amount: per, paid_amount: 0, status: 'pending' }
            saldo = (saldo - (per - interes)).round(2)
          end
          contract_installments.create!(rows)
          update_columns(financed_amount: (total_paid + rows.sum { |r| r[:amount] }).round(2),
                         weeks: [(contract_installments.count * period_scale).round, 1].max)
        end
      end
    end
    reload
  end

  # Reconstruye SOLO las cuotas pendientes con el saldo actual y el mismo monto de pago:
  # menos cuotas = plazo más corto. Las cuotas pagadas quedan intactas como historial.
  def rebuild_pending_schedule!
    pend = contract_installments.where.not(status: 'paid').order(:number).to_a
    rem = balance
    if rem <= 0.009
      contract_installments.where.not(status: 'paid').delete_all
      update_columns(status: 'paid') unless status == 'cancelled'
      return
    end
    return if pend.empty?

    start_num = pend.first.number
    first_due = pend.first.due_date || due_date_for_period(start_num)
    per = [period_payment.to_f, 0.01].max
    contract_installments.where.not(status: 'paid').delete_all

    n = (rem / per).ceil
    n = 1 if n < 1
    acc = 0.0
    rows = (0...n).map do |i|
      amt = i == n - 1 ? (rem - acc).round(2) : [per, (rem - acc)].min.round(2)
      acc = (acc + amt).round(2)
      due_date = case freq
                 when 'monthly'  then first_due >> i
                 when 'biweekly' then first_due + (i * 14)
                 else                 first_due + (i * 7)
                 end
      { number: start_num + i, due_date: due_date, amount: amt, paid_amount: 0, status: 'pending' }
    end
    contract_installments.create!(rows)
    update_columns(weeks: contract_installments.count) if respond_to?(:weeks)
  end

  # Aplica un pago a las cuotas pendientes mas antiguas (auto-completa la tabla).
  # Devuelve el sobrante si el pago excede el saldo.
  def apply_payment!(amount)
    remaining = amount.to_f
    contract_installments.where.not(status: 'paid').order(:number).each do |inst|
      break if remaining <= 0.009
      due = (inst.amount.to_f - inst.paid_amount.to_f).round(2)
      next if due <= 0
      pay = [remaining, due].min
      inst.paid_amount = (inst.paid_amount.to_f + pay).round(2)
      if inst.paid_amount + 0.009 >= inst.amount.to_f
        inst.status = 'paid'
        inst.paid_at = Time.current
      else
        inst.status = 'partial'
      end
      inst.save!
      remaining = (remaining - pay).round(2)
    end
    update!(status: 'paid') if paid_off? && status != 'cancelled'
    remaining.round(2)
  end

end
