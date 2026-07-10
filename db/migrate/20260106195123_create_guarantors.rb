class CreateGuarantors < ActiveRecord::Migration[7.1]
  def change
    create_table :guarantors do |t|
      t.references :order, null: false, foreign_key: true
      t.string :name
      t.string :last_name
      t.string :address1
      t.string :address2
      t.string :zip_code
      t.string :state
      t.string :city
      t.string :phone
      t.string :email

      t.timestamps
    end
  end
end
