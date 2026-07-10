class AddRiskVersionToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :risk_version, :integer
  end
end
