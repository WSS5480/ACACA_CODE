# frozen_string_literal: true

# El número de CONTRATO ahora se asigna al recibir el pago inicial; antes de pagar,
# la compra sólo tiene número de pedido (PED-id). La columna debe aceptar NULL.
class AllowNullContractNumber < ActiveRecord::Migration[7.1]
  def change
    change_column_null :contracts, :contract_number, true
  end
end
