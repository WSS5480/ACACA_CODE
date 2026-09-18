# frozen_string_literal: true

# PAGO EN PESOS (Stripe México) ADEMÁS DE DÓLARES (Stripe EE. UU.).
#
# El contrato, el saldo y TODA la contabilidad siguen en USD: lo único que
# cambia es la moneda en la que se cobra la tarjeta. Cuando el cliente paga en
# pesos, el cargo va a la cuenta de Stripe México por el equivalente del total
# en USD al tipo de cambio del día más el margen (PayCurrency), y el pago se
# guarda en dólares igual que siempre; las columnas nuevas dejan constancia de
# cuánto se cobró, en qué moneda y por cuál cuenta de Stripe.
class AddPayCurrency < ActiveRecord::Migration[7.1]
  def change
    # Cada cuenta de Stripe tiene SU PROPIO cliente: una tarjeta guardada en
    # México no se puede cobrar desde la cuenta de EE. UU. y viceversa.
    add_column :users, :stripe_customer_id_mx, :string unless column_exists?(:users, :stripe_customer_id_mx)
    add_index  :users, :stripe_customer_id_mx unless index_exists?(:users, :stripe_customer_id_mx)
    # Moneda preferida del cliente (la última que eligió): la usa el autopago.
    add_column :users, :pay_currency, :string, default: 'usd' unless column_exists?(:users, :pay_currency)

    # Constancia del cobro real (el importe del pago sigue siendo USD).
    add_column :payments, :charge_currency, :string unless column_exists?(:payments, :charge_currency)
    add_column :payments, :charge_amount, :decimal, precision: 12, scale: 2 unless column_exists?(:payments, :charge_amount)
    add_column :payments, :stripe_account, :string unless column_exists?(:payments, :stripe_account)

    # Lo mismo en el libro contable (para el registro y el paquete del contador).
    if table_exists?(:ledger_entries)
      add_column :ledger_entries, :charge_currency, :string unless column_exists?(:ledger_entries, :charge_currency)
      add_column :ledger_entries, :charge_amount, :decimal, precision: 12, scale: 2 unless column_exists?(:ledger_entries, :charge_amount)
    end

    # De qué cuenta de Stripe viene cada depósito (EE. UU. en USD, México en MXN).
    if table_exists?(:stripe_payouts)
      add_column :stripe_payouts, :account, :string unless column_exists?(:stripe_payouts, :account)
    end
  end
end
