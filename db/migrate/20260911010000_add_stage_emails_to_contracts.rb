# frozen_string_literal: true

# Registro de los CORREOS DE ETAPA enviados por contrato (datos recibidos,
# verificado, aprobado, firmado, entregado): cada etapa se avisa UNA sola vez.
class AddStageEmailsToContracts < ActiveRecord::Migration[7.1]
  def change
    add_column :contracts, :stage_emails, :jsonb, null: false, default: {} unless column_exists?(:contracts, :stage_emails)
  end
end
