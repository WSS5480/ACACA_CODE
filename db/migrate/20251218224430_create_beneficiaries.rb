class CreateBeneficiaries < ActiveRecord::Migration[7.1]
  def change
    create_table :beneficiaries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :last_name
      t.string :email
      t.string :phone
      t.string :address1
      t.string :address2
      t.string :zip_code
      t.string :state
      t.string :city

      t.timestamps
    end
  end
end
