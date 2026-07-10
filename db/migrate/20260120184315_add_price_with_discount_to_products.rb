class AddPriceWithDiscountToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :price_with_discount, :decimal, precision: 10, scale: 2
  end
end
