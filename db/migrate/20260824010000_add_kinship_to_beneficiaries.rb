class AddKinshipToBeneficiaries < ActiveRecord::Migration[7.1]
  def change
    add_column :beneficiaries, :kinship, :string
  end
end
