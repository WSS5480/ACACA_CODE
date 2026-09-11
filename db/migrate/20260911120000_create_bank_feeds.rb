# frozen_string_literal: true

# BANCOS: cuentas bancarias del negocio conectadas al back office para bajar
# movimientos y ver saldos. Diseño agnóstico del proveedor:
#   * provider 'plaid'  → bancos de EE. UU. (token de acceso cifrado por conexión)
#   * provider 'manual' → cualquier banco (México hoy): estados de cuenta importados
#   * (queda lugar para un agregador mexicano: misma tabla, otro provider)
# Los movimientos se guardan CON SIGNO (+ entra, − sale) sin importar el proveedor,
# y cada uno puede quedar ligado a un depósito de Stripe o a un Gasto del libro.
class CreateBankFeeds < ActiveRecord::Migration[7.1]
  def change
    create_table :bank_connections do |t|
      t.string   :provider, null: false            # plaid | manual
      t.string   :external_id, null: false         # Plaid item_id | manual-xxxx
      t.text     :access_token_enc                 # Plaid access_token CIFRADO (nunca en claro)
      t.string   :institution_id
      t.string   :institution_name
      t.string   :country, default: 'US'           # US | MX
      t.string   :status, default: 'active'        # active | login_required | error | disconnected
      t.string   :sync_cursor                      # cursor de /transactions/sync (Plaid)
      t.datetime :last_synced_at
      t.datetime :last_webhook_at
      t.datetime :sync_requested_at                # el webhook solo MARCA; el tick sincroniza
      t.text     :last_error
      t.datetime :disconnected_at
      t.bigint   :created_by_id
      t.jsonb    :meta, default: {}
      t.timestamps
    end
    add_index :bank_connections, %i[provider external_id], unique: true
    add_index :bank_connections, :status

    create_table :bank_accounts do |t|
      t.references :bank_connection, null: false, foreign_key: true
      t.string   :external_id, null: false
      t.string   :name
      t.string   :official_name
      t.string   :mask                             # últimos 4 dígitos
      t.string   :kind                             # depository | credit | loan | investment | other
      t.string   :subtype                          # checking | savings | credit card | ...
      t.string   :currency, default: 'USD'
      t.decimal  :current_balance,   precision: 14, scale: 2
      t.decimal  :available_balance, precision: 14, scale: 2
      t.datetime :balance_as_of
      t.boolean  :active, default: true
      t.jsonb    :meta, default: {}
      t.timestamps
    end
    add_index :bank_accounts, %i[bank_connection_id external_id], unique: true

    create_table :bank_transactions do |t|
      t.references :bank_account, null: false, foreign_key: true
      t.string   :external_id, null: false
      t.date     :posted_on, null: false
      t.date     :authorized_on
      t.decimal  :amount, precision: 14, scale: 2, null: false   # CON SIGNO: + entra, − sale
      t.string   :currency, default: 'USD'
      t.string   :description
      t.string   :merchant_name
      t.string   :category
      t.string   :category_detail
      t.boolean  :pending, default: false
      t.string   :pending_external_id
      t.string   :channel
      t.string   :stripe_payout_id                 # depósito de Stripe identificado
      t.bigint   :expense_id                       # Gasto creado en Contabilidad a partir de este movimiento
      t.datetime :removed_at                       # el banco lo retiró (Plaid 'removed'); se conserva, no se borra
      t.jsonb    :raw, default: {}
      t.timestamps
    end
    add_index :bank_transactions, %i[bank_account_id external_id], unique: true
    add_index :bank_transactions, :posted_on
    add_index :bank_transactions, :stripe_payout_id
    add_index :bank_transactions, :expense_id

    create_table :stripe_payouts do |t|
      t.string   :stripe_id, null: false
      t.decimal  :amount, precision: 14, scale: 2, null: false
      t.string   :currency, default: 'USD'
      t.date     :arrival_on
      t.string   :status                           # paid | pending | in_transit | canceled | failed
      t.string   :description
      t.string   :destination
      t.string   :method
      t.bigint   :bank_transaction_id
      t.datetime :matched_at
      t.jsonb    :raw, default: {}
      t.timestamps
    end
    add_index :stripe_payouts, :stripe_id, unique: true
    add_index :stripe_payouts, :arrival_on
    add_index :stripe_payouts, :bank_transaction_id
  end
end
