class CreateBuyers < ActiveRecord::Migration[7.1]
  def change
    create_table :buyers do |t|
      t.references :order, null: false, foreign_key: true
      t.string :name
      t.string :last_name
      t.string :nationality
      t.string :state_residence
      t.string :living_address1
      t.string :living_address2
      t.string :living_zip_code
      t.string :living_state
      t.string :living_city
      t.string :housing_type
      t.string :months_usa
      t.string :months_address
      t.string :job
      t.string :phone
      t.string :phone_work
      t.string :email
      t.decimal :weekly_income, precision: 10, scale: 2
      t.string :relationship_with_beneficiary
      t.string :delivery_address1
      t.string :delivery_address2
      t.string :delivery_zip_code
      t.string :delivery_state
      t.string :delivery_city
      t.string :phone_beneficiary

      t.timestamps
    end
  end
end
