class ProductCategory < ApplicationRecord
  belongs_to :product
  belongs_to :category

  validates :product_id, uniqueness: { scope: :category_id, message: 'ya está asociado a esta categoría' }
end
