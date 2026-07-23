class AddProductPriceWithDiscountToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :product_price_with_discount, :decimal, precision: 10, scale: 2
  end
end
