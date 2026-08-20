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
  # Miniaturas de los artículos: para VER el producto mientras se atiende al
  # cliente (Órdenes, Gestión de cuenta / banco de trabajo).
  attribute :item_thumbs do |c|
    c.orders.first(4).map do |o|
      img = begin
        o.product&.image_urls&.first
      rescue StandardError
        nil
      end
      { title: (o.respond_to?(:product_title) ? o.product_title : nil), image: img }
    end
  end
  attribute :past_due_amount do |c|
    c.past_due_amount
  end
  # Pago por periodo EXACTO según la frecuencia (semanal x1, quincenal x2, mensual x4.333).
  attribute :period_payment do |c|
    c.respond_to?(:period_payment) ? c.period_payment : c.weekly_payment
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
  # Intereses moratorios acumulados sobre lo vencido (después de 1 día de atraso)
  attribute :late_fee_amount do |c|
    c.respond_to?(:late_fee_amount) ? c.late_fee_amount : 0.0
  end
  # Tasa anual y CAT calculados por contrato (precio de contado, interés, plazo y cuota).
  attribute :annual_interest_rate do |c|
    c.respond_to?(:annual_interest_rate) ? c.annual_interest_rate : nil
  end
  attribute :computed_cat do |c|
    c.respond_to?(:computed_cat) ? c.computed_cat : nil
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
  # Estado del CICLO DE VIDA de la cuenta (Mi cuenta del cliente):
  # pending_initial | missing_info | pending_approval | pending_signature |
  # pending_delivery | active | paid_off
  attribute :account_status do |c|
    c.respond_to?(:account_status) ? c.account_status : nil
  end
  # Expediente completo: comprador + las 4 referencias (2 MX + 2 US)
  attribute :datos_complete do |c|
    c.respond_to?(:datos_complete?) ? c.datos_complete? : true
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
