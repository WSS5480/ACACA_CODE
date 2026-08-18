# frozen_string_literal: true

# 1) Contacto del DOMICILIO del comprador (casero o conocido de la vivienda):
#    a quién le preguntamos si el cliente RENTA o es DUEÑO (plantilla ref_domicilio).
# 2) Cola de VERIFICACIONES por WhatsApp a referencias: al completarse los datos
#    de la compra se encolan y se envían solas en horario local 8am–9pm.
class AddHomeContactAndReferencePings < ActiveRecord::Migration[7.1]
  def change
    add_column :buyers, :home_contact_name, :string unless column_exists?(:buyers, :home_contact_name)
    add_column :buyers, :home_contact_phone, :string unless column_exists?(:buyers, :home_contact_phone)

    create_table :reference_pings do |t|
      t.bigint :contract_id, null: false
      t.string :target_kind, null: false # personal | trabajo | domicilio
      t.string :phone, null: false       # solo dígitos
      t.string :ref_name
      t.string :customer_name
      t.string :status, default: 'pending' # pending | sent | skipped
      t.integer :attempts, default: 0
      t.string :error
      t.datetime :sent_at
      t.timestamps
    end
    add_index :reference_pings, %i[contract_id target_kind phone], unique: true, name: 'idx_reference_pings_unique'
    add_index :reference_pings, :status
  end
end
