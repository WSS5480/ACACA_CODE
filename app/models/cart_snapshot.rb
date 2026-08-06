# frozen_string_literal: true

# Foto del carrito de un cliente con sesión iniciada (para el CRM de carritos
# abandonados). Una fila por cliente; se borra cuando el carrito queda vacío
# o la compra se concreta.
class CartSnapshot < ApplicationRecord
  belongs_to :user

  def items_list
    JSON.parse(items.presence || '[]')
  rescue StandardError
    []
  end
end
