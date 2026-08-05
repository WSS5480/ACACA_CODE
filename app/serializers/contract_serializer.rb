class ContractSerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :contract_number, :status, :total_amount, :downpayment,
             :financed_amount, :weekly_payment, :weeks, :start_date, :created_at

  attribute :client_name do |c|
    [c.user&.name, c.user&.last_name].compact.join(' ').strip
  end
  attribute :client_number do |c|
    c.user&.number
  end
  attribute :balance do |c|
    c.balance
  end
  attribute :total_paid do |c|
    c.total_paid
  end
  attribute :payment_status do |c|
    c.payment_status
  end
  attribute :items_count do |c|
    c.orders.size
  end
  attribute :past_due_amount do |c|
    c.past_due_amount
  end
  attribute :next_due_date do |c|
    c.next_due_date
  end
  attribute :days_past_due do |c|
    c.days_past_due
  end
  attribute :frequency do |c|
    c.freq
  end
  # Cargo financiero (interés implícito): diferencia del factor a 100 (1.25 → 25%).
  attribute :interest_rate do |c|
    c.respond_to?(:interest_rate) ? c.interest_rate : 25.0
  end
  attribute :first_due_date do |c|
    c.first_due_date
  end
  attribute :initial_payment do |c|
    c.initial_payment
  end
  # Pago inicial recibido (false = intento de compra pendiente → CRM)
  attribute :initial_paid do |c|
    c.respond_to?(:initial_paid?) ? c.initial_paid? : true
  end
  # Número de PEDIDO (existe desde el checkout; el número de contrato nace al pagar)
  attribute :order_ref do |c|
    c.respond_to?(:order_ref) ? c.order_ref : "PED-#{c.id}"
  end
  attribute :document_generated do |c|
    c.respond_to?(:document_generated_at) && c.document_generated_at.present?
  end
  attribute :document_signed do |c|
    c.respond_to?(:signed_at) && c.signed_at.present?
  end
  attribute :client_phone do |c|
    c.user&.phone
  end
  attribute :client_email do |c|
    c.user&.email
  end
  attribute :autopay do |c|
    c.respond_to?(:autopay) ? c.autopay : false
  end
  attribute :waiver do |c|
    c.orders.first&.waiver
  end
  attribute :first_order_id do |c|
    c.orders.first&.id
  end

  # pendiente (falta aprobar en Ordenes) -> por_entregar -> entregado
  attribute :fulfillment do |c|
    orders = c.orders.to_a
    if orders.empty?
      nil
    elsif orders.any? { |o| !(o.respond_to?(:admin_approved) && o.admin_approved) }
      'pendiente'
    elsif orders.all? { |o| o.respond_to?(:delivered_at) && o.delivered_at.present? }
      'entregado'
    else
      'por_entregar'
    end
  end
end
