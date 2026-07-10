class CreateRoles < ActiveRecord::Migration[7.1]
  def change
    create_table :roles do |t|
      t.string :name
      t.string :label

      t.timestamps
    end
  end
end
