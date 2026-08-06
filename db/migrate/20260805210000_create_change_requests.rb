# frozen_string_literal: true

# Cambios sensibles con APROBACIÓN POR FIRMAS: lo que se cambie en Tasas e
# impuestos, en Control de documentos legales o al revocar acceso de un usuario
# del equipo queda PENDIENTE hasta reunir 4 firmas de administradores (o todas
# si hay menos de 4). El rol 'sistema' aplica sus cambios directo, sin firmas.
class CreateChangeRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :change_requests do |t|
      t.string :kind, null: false               # 'rates' | 'contract_template' | 'staff_delete'
      t.text :payload                            # JSON con los valores propuestos
      t.text :summary                            # resumen legible (antes → después)
      t.bigint :proposed_by_id, index: true
      t.string :proposed_by_email
      t.string :status, null: false, default: 'pending', index: true # pending | applied | rejected
      t.integer :required_signatures, null: false, default: 4
      t.datetime :applied_at
      t.string :rejected_by_email
      t.timestamps
    end

    create_table :change_signatures do |t|
      t.bigint :change_request_id, null: false, index: true
      t.bigint :user_id
      t.string :user_email
      t.string :user_role
      t.datetime :signed_at, null: false
    end
    add_index :change_signatures, [:change_request_id, :user_id], unique: true, name: 'idx_change_sig_unique'
  end
end
