# frozen_string_literal: true

class AddVerificationToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :beneficiary_verified, :boolean, default: false unless column_exists?(:orders, :beneficiary_verified)
    add_column :orders, :beneficiary_comment, :string unless column_exists?(:orders, :beneficiary_comment)
    add_column :orders, :buyer_verified, :boolean, default: false unless column_exists?(:orders, :buyer_verified)
    add_column :orders, :buyer_comment, :string unless column_exists?(:orders, :buyer_comment)
    add_column :orders, :references_verified, :boolean, default: false unless column_exists?(:orders, :references_verified)
    add_column :orders, :references_comment, :string unless column_exists?(:orders, :references_comment)
    add_column :orders, :admin_approved, :boolean, default: false unless column_exists?(:orders, :admin_approved)
    add_column :orders, :approved_at, :datetime unless column_exists?(:orders, :approved_at)
    add_column :orders, :delivered_at, :datetime unless column_exists?(:orders, :delivered_at)
  end
end
