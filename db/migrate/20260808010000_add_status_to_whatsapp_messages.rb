# frozen_string_literal: true

# Estatus de ENTREGA de los mensajes salientes de WhatsApp (las palomitas):
# sent (✓ enviado) -> delivered (✓✓ entregado) -> read (✓✓ azul leído) · failed (⚠).
# Meta lo reporta por webhook en el campo 'statuses'.
class AddStatusToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_messages, :status, :string unless column_exists?(:whatsapp_messages, :status)
    add_column :whatsapp_messages, :status_at, :datetime unless column_exists?(:whatsapp_messages, :status_at)
    # Motivo EXACTO que reporta Meta cuando un mensaje no se entrega
    # (p. ej. fuera de la ventana de 24 h, número no está en WhatsApp...).
    add_column :whatsapp_messages, :status_error, :string unless column_exists?(:whatsapp_messages, :status_error)
  end
end
