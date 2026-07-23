class CreateCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :categories do |t|
      t.string :name
      t.string :external_id
      t.string :original_link

      t.timestamps
    end
  end
end
