# frozen_string_literal: true

class CreateContractsAndPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :contracts do |t|
      t.bigint :user_id, null: false
      t.string :contract_number, null: false
      t.string :status, null: false, default: 'active'
      t.decimal :total_amount, precision: 10, scale: 2, default: '0.0'
      t.decimal :downpayment, precision: 10, scale: 2, default: '0.0'
      t.decimal :financed_amount, precision: 10, scale: 2, default: '0.0'
      t.decimal :weekly_payment, precision: 10, scale: 2, default: '0.0'
      t.integer :weeks
      t.date :start_date
      t.timestamps
    end
    add_index :contracts, :user_id
    add_index :contracts, :contract_number, unique: true

    create_table :payments do |t|
      t.bigint :contract_id, null: false
      t.bigint :user_id
      t.decimal :amount, precision: 10, scale: 2, null: false, default: '0.0'
      t.datetime :paid_at
      t.string :method
      t.string :note
      t.timestamps
    end
    add_index :payments, :contract_id
    add_index :payments, :user_id

    create_table :contract_installments do |t|
      t.bigint :contract_id, null: false
      t.integer :number, null: false
      t.date :due_date
      t.decimal :amount, precision: 10, scale: 2, default: '0.0'
      t.decimal :paid_amount, precision: 10, scale: 2, default: '0.0'
      t.string :status, null: false, default: 'pending'
      t.datetime :paid_at
      t.timestamps
    end
    add_index :contract_installments, [:contract_id, :number], unique: true

    add_column :orders, :contract_id, :bigint
    add_index :orders, :contract_id

    add_column :credits, :credit_limit, :decimal, precision: 10, scale: 2
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE credits SET credit_limit = amount + COALESCE(
            (SELECT SUM(used_credit) FROM orders WHERE orders.user_id = credits.user_id), 0)
          WHERE credit_limit IS NULL
        SQL
      end
    end
  end
end
