# frozen_string_literal: true

class AddFrequencyToContracts < ActiveRecord::Migration[7.1]
  def change
    add_column :contracts, :frequency, :string, default: 'weekly', null: false unless column_exists?(:contracts, :frequency)
    add_column :contracts, :first_due_date, :date unless column_exists?(:contracts, :first_due_date)
  end
end
