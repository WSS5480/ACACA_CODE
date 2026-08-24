# frozen_string_literal: true

# RECIBOS: el libro contable guarda también lo necesario para reimprimir un
# recibo completo aunque el contrato se elimine después — artículos pagados,
# % de exención de responsabilidad y número de pago (ej. 6/26).
class AddReceiptFieldsToLedgerEntries < ActiveRecord::Migration[7.1]
  def up
    add_column :ledger_entries, :items_label, :string unless column_exists?(:ledger_entries, :items_label)
    add_column :ledger_entries, :waiver_pct, :decimal, precision: 5, scale: 2 unless column_exists?(:ledger_entries, :waiver_pct)
    add_column :ledger_entries, :payment_seq, :string unless column_exists?(:ledger_entries, :payment_seq)

    backfill!
  end

  def down
    %i[items_label waiver_pct payment_seq].each do |c|
      remove_column :ledger_entries, c if column_exists?(:ledger_entries, c)
    end
  end

  private

  def backfill!
    return unless defined?(LedgerEntry)

    LedgerEntry.reset_column_information
    say_with_time 'Backfill: artículos, % exención y no. de pago en el libro' do
      n = 0
      LedgerEntry.where.not(contract_id: nil).find_each do |e|
        c = Contract.find_by(id: e.contract_id)
        next unless c

        items = c.orders.map { |o| o.respond_to?(:product_title) ? o.product_title : nil }.compact.join(' + ')
        total = c.contract_installments.count
        paid  = c.contract_installments.where(status: 'paid').count
        e.update_columns(
          items_label: items.presence&.truncate(180),
          waiver_pct: c.orders.first.try(:waiver).to_f,
          payment_seq: (total.positive? ? "#{paid}/#{total}" : nil)
        )
        n += 1
      end
      n
    end
  end
end
