# frozen_string_literal: true

class AddStripeFields < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :stripe_customer_id, :string unless column_exists?(:users, :stripe_customer_id)
    add_column :payments, :stripe_payment_intent_id, :string unless column_exists?(:payments, :stripe_payment_intent_id)
    add_index :payments, :stripe_payment_intent_id, unique: true unless index_exists?(:payments, :stripe_payment_intent_id)
  end
end
