# frozen_string_literal: true

# Carritos ABANDONADOS: foto del carrito de cada cliente con sesión iniciada.
# Alimenta el CRM (cliente puso artículos y se fue sin llegar al pago).
# Pipeline completo: carrito abandonado / pedido sin pagar -> CRM;
# pago inicial hecho -> Órdenes; entregado -> cuenta del cliente.
class CreateCartSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :cart_snapshots do |t|
      t.bigint :user_id, null: false, index: { unique: true }
      t.text :items                    # JSON [{product_id, title, total_price}]
      t.decimal :total, precision: 12, scale: 2, default: 0
      t.timestamps
    end
  end
end
