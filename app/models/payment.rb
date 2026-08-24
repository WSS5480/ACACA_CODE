# frozen_string_literal: true

# Un pago registrado contra un contrato. Al crearse reduce el saldo y avanza la amortizacion.
# apply_mode: 'plazo' (default: el excedente ADELANTA cuotas futuras) o
#             'saldo'  (el excedente paga PRINCIPAL: acorta el plazo y ahorra el interés/factor).
#
# CONTABILIDAD: cada pago se clasifica solo al crearse (kind) y se copia al libro
# contable (LedgerEntry) — el registro sobrevive aunque el contrato se elimine.
#   enganche    = primer pago de una compra financiada
#   contado     = primer pago que cubre TODO el financiado (venta de contado)
#   renta       = cuota semanal/quincenal/mensual
#   liquidacion = pago que deja el saldo en cero
#   epo         = opción de compra anticipada (se pasa explícito cuando exista el flujo)
class Payment < ApplicationRecord
  KINDS = %w[enganche renta contado liquidacion epo].freeze

  belongs_to :contract
  belongs_to :user, optional: true

  attr_accessor :apply_mode

  validates :amount, numericality: { greater_than: 0 }

  before_validation :set_defaults, on: :create
  before_create :set_accounting_fields
  after_create :apply_to_contract
  after_create :record_in_ledger

  private

  def set_defaults
    self.paid_at ||= Time.current
    self.user_id ||= contract&.user_id
  end

  # Clasificación + tipo de cambio + total. Defensivo: si la migración de
  # contabilidad aún no corre, no hace nada (el pago NUNCA se bloquea por esto).
  def set_accounting_fields
    return unless self.class.column_names.include?('kind')

    if kind.blank?
      prior = contract.payments.sum(:amount).to_f # el pago actual aún no está en la BD
      fin = contract.financed_amount.to_f
      self.kind = if prior <= 0.009
                    fin.positive? && amount.to_f + 0.009 >= fin ? 'contado' : 'enganche'
                  else
                    prior + amount.to_f + 0.009 >= fin ? 'liquidacion' : 'renta'
                  end
    end
    self.fx_rate ||= begin
      defined?(ExchangeRate) ? ExchangeRate.current_rate : nil
    rescue StandardError
      nil
    end
    self.total_charged = (amount.to_f + iva_amount.to_f + extra_amount.to_f).round(2) if total_charged.to_f <= 0
  rescue StandardError => e
    Rails.logger.error "set_accounting_fields pago: #{e.message}"
    self.kind ||= 'renta' if self.class.column_names.include?('kind')
  end

  def apply_to_contract
    # OJO: el pago YA NO asigna número de contrato. El pedido se convierte en
    # CONTRATO hasta que el equipo pulsa "Generar contrato y enviar a firma".
    if apply_mode.to_s == 'saldo' && contract.respond_to?(:apply_payment_saldo!)
      contract.apply_payment_saldo!(amount)
    else
      contract.apply_payment!(amount)
    end
    restore_credit(amount)
  end

  def record_in_ledger
    LedgerEntry.record_payment!(self) if defined?(LedgerEntry)
  rescue StandardError => e
    Rails.logger.error "record_in_ledger pago #{id}: #{e.message}"
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
