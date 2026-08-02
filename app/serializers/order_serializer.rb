class OrderSerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :product_id, :beneficiary_id, :user_name, :user_last_name, :user_email,
             :product_title, :product_asin, :product_price, :product_price_with_discount, :product_original_price,
             :product_turns, :product_decimal_factor, :used_credit, :downpayment,
             :weekly_payment, :credit_duration, :status, :hightouch_id, :waiver, :created_at, :updated_at

  attribute :product_image_url do |order|
    order.product&.image_urls&.first
  end

  attribute :contract_id do |order|
    order.respond_to?(:contract_id) ? order.contract_id : nil
  end

  attribute :contract_number do |order|
    order.respond_to?(:contract) ? order.contract&.contract_number : nil
  end

  %i[beneficiary_verified beneficiary_comment buyer_verified buyer_comment
     references_verified references_comment admin_approved approved_at delivered_at].each do |f|
    attribute f do |order|
      order.respond_to?(f) ? order.public_send(f) : nil
    end
  end

  # pendiente -> aprobado (por entregar) -> entregado
  attribute :fulfillment_status do |order|
    if order.respond_to?(:delivered_at) && order.delivered_at.present?
      'entregado'
    elsif order.respond_to?(:admin_approved) && order.admin_approved
      'por_entregar'
    else
      'pendiente'
    end
  end
end

