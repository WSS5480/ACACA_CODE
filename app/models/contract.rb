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

  # current / past_due / paid / cancelled
  def payment_status
    return 'cancelled' if status == 'cancelled'
    return 'paid' if status == 'paid' || paid_off?
    overdue? ? 'past_due' : 'current'
  end

  # ----- amortizacion -----
  # Genera la tabla semanal: N cuotas, cada una = pago semanal, sumando el monto financiado.
  def build_amortization!(start: nil)
    start ||= start_date || Date.current
    contract_installments.delete_all
    n = weeks.to_i
    return if n <= 0
    total = financed_amount.to_f
    wk = weekly_payment.to_f > 0 ? weekly_payment.to_f : (total / n)
    acc = 0.0
    rows = (1..n).map do |i|
      amt = (i == n) ? (total - acc).round(2) : wk.round(2)
      acc = (acc + amt).round(2)
      { number: i, due_date: start + (i * 7), amount: amt, paid_amount: 0, status: 'pending' }
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
