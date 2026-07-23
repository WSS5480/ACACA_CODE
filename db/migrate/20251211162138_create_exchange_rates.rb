class CreateExchangeRates < ActiveRecord::Migration[7.1]
  def change
    create_table :exchange_rates do |t|
      t.decimal :usd_to_mxn, precision: 10, scale: 2

      t.timestamps
    end
  end
end
