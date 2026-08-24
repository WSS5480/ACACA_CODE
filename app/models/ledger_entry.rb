# frozen_string_literal: true

# LIBRO CONTABLE (append-only): cada movimiento de dinero — pagos, reembolsos,
# contracargos y ajustes — queda registrado aquí con su desglose y NO se borra
# aunque el contrato o el pago se eliminen después. Es la fuente del Registro
# de transacciones, los cortes y el estado de resultados.
class LedgerEntry < ApplicationRecord
  KINDS  = %w[enganche renta contado liquidacion epo reembolso contracargo ajuste].freeze
  INCOME = %w[enganche renta contado liquidacion epo].freeze     # ingresos
  CONTRA = %w[reembolso contracargo].freeze                      # contra-ingresos (negativos)

  validates :kind, inclusion: { in: KINDS }
  validates :amount, numericality: { other_than: 0 }

  # Copia un pago al libro (idempotente por payment_id). NUNCA rompe el pago:
  # cualquier error se registra en el log y se sigue adelante.
  def self.record_payment!(p)
    return unless table_exists?
    return if where(payment_id: p.id).exists?

    c = p.contract
    u = p.user || c&.user
    attrs = {
      entry_date: (p.paid_at || Time.current).in_time_zone('America/Monterrey').to_date,
      happened_at: p.paid_at || Time.current,
      kind: (p.try(:kind).presence || 'renta'),
      amount: (p.try(:total_charged).to_f.positive? ? p.total_charged : p.amount).to_f.round(2),
      base_amount: p.amount.to_f.round(2),
      iva_amount: p.try(:iva_amount).to_f.round(2),
      extra_amount: p.try(:extra_amount).to_f.round(2),
      stripe_fee: p.try(:stripe_fee).to_f.round(2),
      fx_rate: p.try(:fx_rate),
      method: p.method,
      reference: (p.respond_to?(:stripe_payment_intent_id) && p.stripe_payment_intent_id.presence) || "pago ##{p.id}",
      description: p.note.to_s.truncate(180).presence,
      contract_label: c ? (c.contract_number.presence || c.order_ref) : nil,
      client_name: [u&.name, u&.last_name].compact.join(' ').presence,
      payment_id: p.id, contract_id: p.contract_id, user_id: u&.id
    }
    # Datos del RECIBO (artículos, % de exención y no. de pago) — defensivo por
    # si la migración de recibos aún no ha corrido en producción.
    if column_names.include?('items_label') && c
      items = c.orders.map { |o| o.respond_to?(:product_title) ? o.product_title : nil }.compact.join(' + ')
      total = c.contract_installments.count
      paid  = c.contract_installments.where(status: 'paid').count
      attrs[:items_label] = items.presence&.truncate(180)
      attrs[:waiver_pct] = c.orders.first.try(:waiver).to_f
      attrs[:payment_seq] = (total.positive? ? "#{paid}/#{total}" : nil)
    end
    create!(attrs)
  rescue StandardError => e
    Rails.logger.error "[Ledger] record_payment! pago #{p.id}: #{e.message}"
    nil
  end

  # Reembolso de un pago (Stripe o manual): entra como renglón NEGATIVO.
  # Si el desglose guardado no cuadra con el total reembolsado, el IVA absorbe
  # la diferencia (reembolsos parciales de cargos combinados).
  def self.record_refund!(contract:, total:, payment: nil, reference: nil, by: nil, description: nil, kind: 'reembolso')
    return unless table_exists?

    tot   = -total.to_f.abs.round(2)
    base  = -(payment&.amount.to_f.round(2))
    iva   = -(payment.try(:iva_amount).to_f.round(2))
    extra = -(payment.try(:extra_amount).to_f.round(2))
    if payment.nil? || (base + iva + extra - tot).abs > 0.02
      base = tot - iva - extra
      base = tot if payment.nil?
      iva = 0 if payment.nil?
      extra = 0 if payment.nil?
    end
    u = contract&.user
    create!(
      entry_date: Time.current.in_time_zone('America/Monterrey').to_date,
      happened_at: Time.current,
      kind: kind, amount: tot, base_amount: base.round(2), iva_amount: iva.to_f.round(2), extra_amount: extra.to_f.round(2),
      method: payment&.method || 'stripe',
      reference: reference.presence || 'reembolso',
      description: description.presence || 'Reembolso a la forma de pago original',
      contract_label: contract ? (contract.contract_number.presence || contract.order_ref) : nil,
      client_name: [u&.name, u&.last_name].compact.join(' ').presence,
      contract_id: contract&.id, user_id: u&.id, created_by_id: by&.id
    )
  rescue StandardError => e
    Rails.logger.error "[Ledger] record_refund!: #{e.message}"
    nil
  end
end
