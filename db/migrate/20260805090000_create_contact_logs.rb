# frozen_string_literal: true

# Bitácora de conversaciones (llamadas, notas) por persona: cliente/comprador,
# beneficiario o referencia. Vive junto al historial de WhatsApp en el mismo popup.
class CreateContactLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :contact_logs do |t|
      t.references :user, foreign_key: false, index: true # cuenta del cliente
      t.bigint :order_id, index: true                     # orden relacionada (opcional)
      t.string :person_type                               # customer | buyer | beneficiary | reference
      t.string :person_name
      t.string :phone                                     # tel. de la persona (dígitos)
      t.text :body, null: false                           # la nota / resumen de la llamada
      t.bigint :author_id                                 # staff que registró
      t.string :author_name
      t.timestamps
    end
    add_index :contact_logs, :phone
  end
end
