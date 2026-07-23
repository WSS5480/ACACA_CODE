class AddFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :name, :string
    add_column :users, :last_name, :string
    add_column :users, :number, :string
    add_column :users, :phone, :string
    add_column :users, :housing_type, :string
    add_column :users, :years_usa, :string
    add_column :users, :years_address, :string
    add_column :users, :years_job, :string
    add_column :users, :estimated_income, :string
    add_column :users, :delivery_country, :string
    add_column :users, :shared_income, :string
  end
end
