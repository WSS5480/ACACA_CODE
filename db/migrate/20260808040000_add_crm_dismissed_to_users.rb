# frozen_string_literal: true

# Marca de "LIBERADO del CRM": cuentas nuevas que nunca compraron y que el
# equipo decidió soltar tras no poder contactarlas. No borra la cuenta —
# solo la saca de la lista de seguimiento.
class AddCrmDismissedToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :crm_dismissed_at, :datetime unless column_exists?(:users, :crm_dismissed_at)
  end
end
