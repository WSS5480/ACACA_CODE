class ProductSerializer
  include JSONAPI::Serializer

  attributes :id, :title, :keywords, :asin, :original_link, :brand, :rating,
             :feature_bullets, :price, :price_with_discount, :currency, :color, :material,
             :dimensions, :model_number, :external_id, :status, :min_weekly_payment, :turns, :decimal_factor,
             :original_price, :created_at, :updated_at

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

