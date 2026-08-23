class AddAmazonFlagsToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :sold_by_amazon, :boolean
    add_column :products, :delivered_by_amazon, :boolean
    add_column :products, :main_photo_ok, :boolean
  end
end
