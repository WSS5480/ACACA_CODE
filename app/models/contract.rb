# frozen_string_literal: true

# Un Contrato agrupa uno o mas articulos (orders) de un cliente bajo un solo numero de contrato,
# con UN pago semanal combinado, una tabla de amortizacion, y un saldo que baja con cada pago.
class Contract < ApplicationRecord
  belongs_to :user
  has_many :orders, dependent: :nullify
  has_many :payments, dependent: :destroy
  has_many :contract_installments, -> { order(:number) }, dependent: :destroy

  STATUSES = %w[active paid cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :contract_number, presence: true, uniqueness: true

  before_validation :ensure_number, on: :create

  # ----- dinero -----
  def total_paid
    payments.sum(:amount).to_f
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
    loop do
      candidate = "C#{Time.current.strftime('%y%m')}#{SecureRandom.random_number(100000).to_s.rjust(5, '0')}"
      unless Contract.exists?(contract_number: candidate)
        self.contract_number = candidate
        break
      end
    end
  end
end
