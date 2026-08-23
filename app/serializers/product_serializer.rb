class ProductSerializer
  include JSONAPI::Serializer

  attributes :id, :title, :keywords, :asin, :original_link, :brand, :rating,
             :feature_bullets, :price, :price_with_discount, :currency, :color, :material,
             :dimensions, :model_number, :external_id, :status, :turns, :decimal_factor,
             :original_price, :created_at, :updated_at

  # Respuestas guardadas AL DESCARGAR (sin verificaciones posteriores):
  attribute :sold_by_amazon do |p|
    p.respond_to?(:sold_by_amazon) ? p.sold_by_amazon : nil
  end
  attribute :delivered_by_amazon do |p|
    p.respond_to?(:delivered_by_amazon) ? p.delivered_by_amazon : nil
  end
  attribute :main_photo_ok do |p|
    p.respond_to?(:main_photo_ok) ? p.main_photo_ok : nil
  end

  attribute :min_weekly_payment do |product|
    product.recalculated_min_weekly_payment
  end

  attribute :total_price do |product|
    product.total_price
  end

  attribute :full_price do |product|
    product.full_price
  end

  attribute :image_urls do |product|
    product.image_urls
  end

  attribute :categories do |product|
    product.categories.map do |category|
      {
        id: category.id,
        name: category.name,
        external_id: category.external_id
      }
    end
  end
end

