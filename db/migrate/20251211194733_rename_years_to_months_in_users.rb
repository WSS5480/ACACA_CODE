class RenameYearsToMonthsInUsers < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :years_usa, :months_usa
    rename_column :users, :years_address, :months_address
    rename_column :users, :years_job, :months_job
  end
end
