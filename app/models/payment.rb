# frozen_string_literal: true

# Un pago registrado contra un contrato. Al crearse reduce el saldo y avanza la amortizacion.
class Payment < ApplicationRecord
  belongs_to :contract
  belongs_to :user, optional: true

  validates :amount, numericality: { greater_than: 0 }

  before_validation :set_defaults, on: :create
  after_create :apply_to_contract

  private

  def set_defaults
    self.paid_at ||= Time.current
    self.user_id ||= contract&.user_id
  end

  def apply_to_contract
    # El PRIMER pago convierte el pedido en contrato: se asigna el número de contrato.
    contract.assign_contract_number! if contract.respond_to?(:assign_contract_number!)
    contract.apply_payment!(amount)
    restore_credit(amount)
  end

  # Al pagar, se restaura credito disponible (hasta el limite de la linea).
  def restore_credit(amt)
    cr = contract&.user&.credit
    return unless cr
    limit = (cr.respond_to?(:credit_limit) ? cr.credit_limit : nil) || cr.amount
    new_amount = [cr.amount.to_f + amt.to_f, limit.to_f].min.round(2)
    cr.update_column(:amount, new_amount)
  rescue StandardError => e
    Rails.logger.error "restore_credit failed: #{e.message}"
  end
end
