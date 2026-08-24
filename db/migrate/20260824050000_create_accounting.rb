# frozen_string_literal: true

# CONTABILIDAD: libro de movimientos (ledger), gastos y cortes (diario/mensual).
# Además clasifica cada pago (enganche/renta/contado/liquidación/EPO) y guarda
# su desglose: base, IVA, exención, total cobrado, comisión de Stripe y tipo de cambio.
class CreateAccounting < ActiveRecord::Migration[7.1]
  def up
    # --- payments: categoría y desglose contable ---
    add_column :payments, :kind, :string unless column_exists?(:payments, :kind)
    add_column :payments, :iva_amount,    :decimal, precision: 10, scale: 2, default: 0 unless column_exists?(:payments, :iva_amount)
    add_column :payments, :extra_amount,  :decimal, precision: 10, scale: 2, default: 0 unless column_exists?(:payments, :extra_amount)
    add_column :payments, :total_charged, :decimal, precision: 10, scale: 2 unless column_exists?(:payments, :total_charged)
    add_column :payments, :stripe_fee,    :decimal, precision: 10, scale: 2 unless column_exists?(:payments, :stripe_fee)
    add_column :payments, :fx_rate,       :decimal, precision: 10, scale: 4 unless column_exists?(:payments, :fx_rate)

    # --- libro contable (append-only): cada movimiento de dinero queda aquí y
    #     SOBREVIVE aunque el contrato/pago se elimine después (reembolsos, purgas). ---
    unless table_exists?(:ledger_entries)
      create_table :ledger_entries do |t|
        t.date     :entry_date, null: false
        t.datetime :happened_at
        t.string   :kind, null: false                                    # enganche|renta|contado|liquidacion|epo|reembolso|contracargo|ajuste
        t.decimal  :amount,       precision: 12, scale: 2, null: false   # TOTAL cobrado/devuelto CON signo (incluye IVA y extras)
        t.decimal  :base_amount,  precision: 12, scale: 2, default: 0    # parte aplicada a la amortización
        t.decimal  :iva_amount,   precision: 12, scale: 2, default: 0
        t.decimal  :extra_amount, precision: 12, scale: 2, default: 0    # exención de responsabilidad
        t.decimal  :stripe_fee,   precision: 12, scale: 2, default: 0
        t.decimal  :fx_rate,      precision: 10, scale: 4
        t.string   :method
        t.string   :reference
        t.string   :description
        t.string   :contract_label
        t.string   :client_name
        t.bigint   :payment_id
        t.bigint   :contract_id
        t.bigint   :user_id
        t.bigint   :created_by_id
        t.timestamps
      end
      add_index :ledger_entries, :entry_date
      add_index :ledger_entries, :kind
      add_index :ledger_entries, :payment_id
    end

    # --- gastos (para el estado de resultados) ---
    unless table_exists?(:expenses)
      create_table :expenses do |t|
        t.date    :expense_date, null: false
        t.string  :category, null: false      # producto|envio|comisiones|publicidad|nomina|software|incobrable|otro
        t.string  :description
        t.string  :vendor
        t.decimal :amount, precision: 12, scale: 2, null: false # negativo = reversión
        t.string  :method
        t.string  :reference
        t.bigint  :contract_id
        t.bigint  :created_by_id
        t.timestamps
      end
      add_index :expenses, :expense_date
      add_index :expenses, :category
    end

    # --- cortes contables (inmutables una vez corridos) ---
    unless table_exists?(:accounting_closes)
      create_table :accounting_closes do |t|
        t.string   :period_type, null: false  # daily | monthly
        t.date     :period_date, null: false
        t.jsonb    :data, default: {}
        t.datetime :run_at
        t.bigint   :run_by_id
        t.timestamps
      end
      add_index :accounting_closes, [:period_type, :period_date], unique: true
    end

    backfill!
  end

  def down
    drop_table :accounting_closes if table_exists?(:accounting_closes)
    drop_table :expenses if table_exists?(:expenses)
    drop_table :ledger_entries if table_exists?(:ledger_entries)
    %i[kind iva_amount extra_amount total_charged stripe_fee fx_rate].each do |c|
      remove_column :payments, c if column_exists?(:payments, c)
    end
  end

  private

  # Clasifica los pagos EXISTENTES y los copia al libro (pocos renglones hoy).
  # El desglose (IVA/exención/total) se rescata de la nota del pago.
  def backfill!
    return unless defined?(Payment) && defined?(LedgerEntry)

    Payment.reset_column_information
    LedgerEntry.reset_column_information
    say_with_time 'Backfill: clasificar pagos y poblar ledger_entries' do
      n = 0
      Contract.includes(:payments, :user).find_each do |c|
        run = 0.0
        fin = c.financed_amount.to_f
        c.payments.sort_by(&:id).each do |p|
          note  = p.note.to_s
          iva   = note[/IVA \$([\d.,]+)/, 1].to_s.delete(',').to_f.round(2)
          extra = note[/exención[^$]*\$([\d.,]+)/i, 1].to_s.delete(',').to_f.round(2)
          total = note[/total cobrado \$([\d.,]+)/, 1].to_s.delete(',').to_f.round(2)
          total = (p.amount.to_f + iva + extra).round(2) if total <= 0
          kind = if run <= 0.009
                   fin.positive? && p.amount.to_f + 0.009 >= fin ? 'contado' : 'enganche'
                 else
                   run + p.amount.to_f + 0.009 >= fin ? 'liquidacion' : 'renta'
                 end
          run += p.amount.to_f
          p.update_columns(kind: kind, iva_amount: iva, extra_amount: extra, total_charged: total)
          next if LedgerEntry.exists?(payment_id: p.id)

          u = c.user
          LedgerEntry.create!(
            entry_date: (p.paid_at || p.created_at).in_time_zone('America/Monterrey').to_date,
            happened_at: p.paid_at || p.created_at,
            kind: kind, amount: total, base_amount: p.amount.to_f.round(2),
            iva_amount: iva, extra_amount: extra,
            method: p.method,
            reference: (p.respond_to?(:stripe_payment_intent_id) && p.stripe_payment_intent_id.presence) || "pago ##{p.id}",
            description: note.truncate(180).presence,
            contract_label: c.contract_number.presence || "PED-#{c.id}",
            client_name: [u&.name, u&.last_name].compact.join(' ').presence,
            payment_id: p.id, contract_id: c.id, user_id: c.user_id
          )
          n += 1
        end
      end
      n
    end
  end
end
