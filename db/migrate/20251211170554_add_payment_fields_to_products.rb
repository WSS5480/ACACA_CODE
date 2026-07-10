class AddPaymentFieldsToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :min_weekly_payment, :decimal, precision: 10, scale: 2
    add_column :products, :turns, :decimal, precision: 10, scale: 2, default: 3.5
    add_column :products, :decimal_factor, :decimal, precision: 10, scale: 2, default: 0.75
    add_column :products, :status, :string, default: 'active'
  end
end
