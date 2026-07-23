class CategorySerializer
  include JSONAPI::Serializer

  attributes :id, :name, :external_id, :original_link, :created_at, :updated_at

  attribute :products_count do |category|
    category.products.count
  end
end

