class CreateReferrals < ActiveRecord::Migration[7.1]
  def change
    create_table :referrals do |t|
      t.references :order, null: false, foreign_key: true
      t.string :nationality
      t.string :name
      t.string :last_name
      t.string :phone
      t.string :phone_work

      t.timestamps
    end
  end
end
