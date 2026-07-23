class AddWaiverToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :waiver, :decimal, precision: 10, scale: 2, default: 0
  end
end
