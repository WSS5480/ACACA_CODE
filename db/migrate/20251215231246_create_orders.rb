class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :user, null: true, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.string :user_name
      t.string :user_last_name
      t.string :user_email
      t.string :product_title
      t.string :product_asin
      t.decimal :product_price, precision: 10, scale: 2
      t.decimal :product_original_price, precision: 10, scale: 2
      t.decimal :product_turns, precision: 10, scale: 2
      t.decimal :product_decimal_factor, precision: 10, scale: 2
      t.decimal :used_credit, precision: 10, scale: 2
      t.decimal :downpayment, precision: 10, scale: 2
      t.decimal :weekly_payment, precision: 10, scale: 2
      t.integer :credit_duration
      t.string :status, default: 'pending'

      t.timestamps
    end
  end
end
