class CreateZipCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :zip_codes do |t|
      t.string :code
      t.string :country
      t.string :state_initials
      t.string :state_name
      t.string :city
      t.string :municipality
      t.string :settlement

      t.timestamps
    end

    add_index :zip_codes, :code
    add_index :zip_codes, :country
    add_index :zip_codes, :state_initials
    add_index :zip_codes, :state_name
    add_index :zip_codes, :city
  end
end
