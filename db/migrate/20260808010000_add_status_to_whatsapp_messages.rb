# frozen_string_literal: true

# Estatus de ENTREGA de los mensajes salientes de WhatsApp (las palomitas):
# sent (✓ enviado) -> delivered (✓✓ entregado) -> read (✓✓ azul leído) · failed (⚠).
# Meta lo reporta por webhook en el campo 'statuses'.
class AddStatusToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_messages, :status, :string unless column_exists?(:whatsapp_messages, :status)
    add_column :whatsapp_messages, :status_at, :datetime unless column_exists?(:whatsapp_messages, :status_at)
  end
end
