# frozen_string_literal: true

class CreateWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_messages do |t|
      t.references :user, foreign_key: false, index: true
      t.string :direction, null: false, default: 'in' # in | out
      t.string :wa_phone                               # numero del cliente (digitos)
      t.text :body
      t.string :media_type                             # image / document / audio / video / sticker
      t.string :wa_message_id
      t.bigint :sent_by_id                             # staff que envio (out)
      t.timestamps
    end
    add_index :whatsapp_messages, :wa_message_id, unique: true
  end
end
