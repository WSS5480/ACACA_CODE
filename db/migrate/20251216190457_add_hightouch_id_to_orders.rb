class AddHightouchIdToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :hightouch_id, :string
    add_index :orders, :hightouch_id
  end
end
