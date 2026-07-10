class CreateSpecificationsLists < ActiveRecord::Migration[7.1]
  def change
    create_table :specifications_lists do |t|
      t.references :product, null: false, foreign_key: true
      t.text :bullets

      t.timestamps
    end
  end
end
