# frozen_string_literal: true

# Nota de conversación registrada por el staff (llamada, visita, acuerdo, etc.)
# ligada a una persona: el cliente, el comprador de una orden, el beneficiario
# o una referencia. Se muestra intercalada con los mensajes de WhatsApp.
class ContactLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :body, presence: true

  # Últimos 10 dígitos para casar teléfonos con/sin lada de país.
  def self.phone_tail(raw)
    d = raw.to_s.gsub(/\D/, '')
    d.length > 10 ? d[-10..] : d
  end

  scope :for_phone, ->(raw) {
    tail = phone_tail(raw)
    tail.present? ? where("regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{tail}") : none
  }
end
