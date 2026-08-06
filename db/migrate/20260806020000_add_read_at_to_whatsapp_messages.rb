# frozen_string_literal: true

# Bandeja de WhatsApp: marca de LEÍDO por mensaje entrante. Un hilo con
# mensajes entrantes sin read_at cuenta como "no leído" (globo verde del menú).
class AddReadAtToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_messages, :read_at, :datetime
    add_index :whatsapp_messages, :read_at
  end
end
