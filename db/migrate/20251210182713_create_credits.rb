class CreateCredits < ActiveRecord::Migration[7.1]
  def change
    create_table :credits do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, default: 0, null: false

      t.timestamps
    end
  end
end
