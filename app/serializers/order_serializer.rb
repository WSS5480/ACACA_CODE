class OrderSerializer
  include JSONAPI::Serializer

  attributes :id, :user_id, :product_id, :beneficiary_id, :user_name, :user_last_name, :user_email,
             :product_title, :product_asin, :product_price, :product_price_with_discount, :product_original_price,
             :product_turns, :product_decimal_factor, :used_credit, :downpayment,
             :weekly_payment, :credit_duration, :status, :hightouch_id, :waiver, :created_at, :updated_at

  attribute :product_image_url do |order|
    order.product&.image_urls&.first
  end
end

