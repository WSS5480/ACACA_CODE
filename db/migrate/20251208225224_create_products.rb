class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.string :title
      t.string :keywords
      t.string :asin
      t.text :original_link
      t.string :brand
      t.float :rating
      t.text :feature_bullets
      t.decimal :price, precision: 10, scale: 2
      t.string :currency
      t.string :color
      t.string :material
      t.string :dimensions
      t.string :model_number
      t.string :external_id

      t.timestamps
    end

    add_index :products, :asin, unique: true
    add_index :products, :external_id
  end
end
