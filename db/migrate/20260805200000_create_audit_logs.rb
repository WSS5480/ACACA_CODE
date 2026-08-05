# frozen_string_literal: true

# Bitácora de auditoría: QUIÉN hizo QUÉ y CUÁNDO — cambios de tasas, pagos
# registrados, aprobaciones de contratos, entregas, firmas, eliminaciones, etc.
class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs do |t|
      t.bigint :user_id, index: true      # quién lo hizo (staff o cliente)
      t.string :user_email                 # denormalizado: sobrevive si se borra el usuario
      t.string :user_role
      t.string :action, index: true        # rates_updated | payment_recorded | order_approved | ...
      t.string :target_type                # Contract / Order / User / AppSetting...
      t.bigint :target_id
      t.string :target_label               # "Contrato C260823741", "Cliente Eddie Cantu"...
      t.text :details                      # resumen legible (antes → después, montos, etc.)
      t.datetime :created_at, null: false, index: true
    end
  end
end
