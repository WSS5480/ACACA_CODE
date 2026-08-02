# frozen_string_literal: true

class AddAutopayToContracts < ActiveRecord::Migration[7.1]
  def change
    add_column :contracts, :autopay, :boolean, default: false, null: false unless column_exists?(:contracts, :autopay)
    add_column :contracts, :autopay_last_error, :string unless column_exists?(:contracts, :autopay_last_error)
  end
end
