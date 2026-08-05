# frozen_string_literal: true

# Un Contrato agrupa uno o mas articulos (orders) de un cliente bajo un solo numero de contrato,
# con UN pago semanal combinado, una tabla de amortizacion, y un saldo que baja con cada pago.
class Contract < ApplicationRecord
  belongs_to :user
  has_many :orders, dependent: :nullify
  has_many :payments, dependent: :destroy
  has_many :contract_installments, -> { order(:number) }, dependent: :destroy
  has_one_attached :signature # firma electrónica del cliente (imagen)

  STATUSES = %w[active paid cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  # El número de CONTRATO se asigna hasta recibir el pago inicial; antes de pagar,
  # la compra sólo tiene número de PEDIDO (order_ref). Contado ('paid') lo recibe al crearse.
  validates :contract_number, uniqueness: true, allow_nil: true

  before_validation :ensure_number, on: :create

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

  # current / past_due / paid / cancelled
  def payment_status
    return 'cancelled' if status == 'cancelled'
    return 'paid' if status == 'paid' || paid_off?
    overdue? ? 'past_due' : 'current'
  end

  # ----- amortizacion -----
  # Genera la tabla semanal: N cuotas, cada una = pago semanal, sumando el monto financiado.
  FREQUENCIES = %w[weekly biweekly monthly].freeze

  def freq
    frequency.presence || 'weekly'
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

  # Pago inicial en el checkout = enganche + primer pago del periodo.
  def initial_payment
    (downpayment.to_f + first_period_payment).round(2)
  end

  def build_amortization!(start: nil)
    contract_installments.delete_all
    self.first_due_date ||= self.class.aligned_first_due(freq, start_date || Date.current)
    save!(validate: false) if changed?
    n, per = schedule_periods_and_amount
    return if n <= 0
    total = financed_amount.to_f
    acc = 0.0
    rows = (1..n).map do |i|
      amt = (i == n) ? (total - acc).round(2) : per.round(2)
      acc = (acc + amt).round(2)
      { number: i, due_date: due_date_for_period(i), amount: amt, paid_amount: 0, status: 'pending' }
    end
    contract_installments.create!(rows)
  end

  # Cargo financiero implícito del modelo: la diferencia del factor a 100.
  # factor 1.25 → 25% sobre el principal financiado.
  def finance_factor
    defined?(Product::FINANCE_FACTOR) ? Product::FINANCE_FACTOR : 1.25
  end

  def interest_rate
    ((finance_factor - 1) * 100).round(2)
  end

  # Pago aplicado a SALDO: el excedente (más allá de la cuota próxima pendiente) paga
  # PRINCIPAL directo, así que se le perdona el cargo financiero (factor − 1) sobre ese
  # excedente → el saldo baja por 1.25x el extra, el plazo se ACORTA y se ahorra interés.
  # (El modo normal/PLAZO usa apply_payment!: el extra adelanta cuotas futuras.)
  def apply_payment_saldo!(amount)
    nxt = contract_installments.where.not(status: 'paid').order(:number).first
    due = nxt ? (nxt.amount.to_f - nxt.paid_amount.to_f).round(2) : 0.0
    cover = [amount.to_f, due].min.round(2)
    extra = (amount.to_f - cover).round(2)

    apply_payment!(cover) if cover.positive?

    if extra.positive?
      rebate = (extra * (finance_factor - 1)).round(2)
      new_fin = [(financed_amount.to_f - rebate).round(2), total_paid].max
      update_columns(financed_amount: new_fin)
      rebuild_pending_schedule!
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

  private

  def ensure_number
    return if contract_number.present?
    # Sólo las ventas de CONTADO nacen con número de contrato (nacen pagadas);
    # a crédito, el número se asigna al recibir el pago inicial (assign_contract_number!).
    return unless status == 'paid'
    loop do
      candidate = "C#{Time.current.strftime('%y%m')}#{SecureRandom.random_number(100000).to_s.rjust(5, '0')}"
      unless Contract.exists?(contract_number: candidate)
        self.contract_number = candidate
        break
      end
    end
  end
end
