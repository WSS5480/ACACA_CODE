# frozen_string_literal: true

# COMPROMISOS DE PAGO acordados con el cliente (cobranza).
# Al registrarse se le avisa por WhatsApp y, el DÍA ANTERIOR a la fecha
# prometida, la plataforma manda sola el recordatorio. Todo queda en la
# bitácora de la persona.
class CreatePaymentCommitments < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_commitments do |t|
      t.bigint  :user_id
      t.bigint  :contract_id
      t.decimal :amount, precision: 12, scale: 2
      t.date    :due_on, null: false
      t.string  :phone
      t.string  :person_name
      t.text    :note
      t.string  :status, default: 'pending' # pending | kept | broken | cancelled
      t.datetime :confirmed_at              # aviso enviado al registrarlo
      t.datetime :reminded_at               # recordatorio del día anterior
      t.bigint  :created_by_id
      t.string  :created_by_name
      t.timestamps
    end
    add_index :payment_commitments, :due_on
    add_index :payment_commitments, :user_id
    add_index :payment_commitments, %i[status due_on]
  end
end
