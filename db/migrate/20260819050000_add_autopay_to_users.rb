# frozen_string_literal: true

# PAGO AUTOMÁTICO a nivel CUENTA: con su tarjeta guardada, el cliente activa el
# cobro automático de TODOS sus contratos según los términos de cada uno; los
# contratos nuevos nacen con el mismo ajuste.
class AddAutopayToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :autopay, :boolean, default: false unless column_exists?(:users, :autopay)
  end
end
