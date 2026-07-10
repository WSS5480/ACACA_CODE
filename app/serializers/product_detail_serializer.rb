class ProductDetailSerializer < ProductSerializer
  attribute :specifications_list do |product|
    if product.specifications_list.present?
      {
        id: product.specifications_list.id,
        bullets: product.specifications_list.bullets
      }
    end
  end
end

