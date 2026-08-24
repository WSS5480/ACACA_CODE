# frozen_string_literal: true

require 'csv'

# PAQUETE MENSUAL PARA EL CONTADOR: al correr el corte mensual (o con el botón
# "Enviar paquete" en Contabilidad) se manda un correo con 3 CSV adjuntos:
# registro de transacciones, gastos y estado de resultados del mes.
class AccountingMailer < ApplicationMailer
  def monthly_package(month_start)
    to = AppSetting.get('accounting_email').to_s
    return if to.blank?

    from = month_start.to_date.beginning_of_month
    to_d = from.end_of_month
    tag  = from.strftime('%Y_%m')
    sum  = AccountingClose.summarize(from, to_d)

    attachments["registro_#{tag}.csv"] = csv_entries(LedgerEntry.where(entry_date: from..to_d).order(:happened_at, :id))
    attachments["gastos_#{tag}.csv"] = csv_expenses(Expense.where(expense_date: from..to_d).order(:expense_date, :id))
    attachments["estado_resultados_#{tag}.csv"] = csv_pnl(sum)

    mail(to: to, subject: "Ácasa · Paquete contable #{from.strftime('%Y-%m')}",
         body: <<~TXT)
      Paquete contable de Ácasa — #{from.strftime('%Y-%m')}

      Depósito neto del mes: $#{format('%.2f', sum[:deposit_net])}
      Ingreso neto (sin IVA): $#{format('%.2f', sum[:revenue_net])}
      IVA neto cobrado: $#{format('%.2f', sum[:iva_net])}
      Comisiones Stripe: $#{format('%.2f', sum[:stripe_fees])}
      Gastos: $#{format('%.2f', sum[:expenses_total])}
      Utilidad neta: $#{format('%.2f', sum[:net_profit])}

      Se adjuntan el registro de transacciones, los gastos y el estado de
      resultados del mes en CSV. Este correo se genera automáticamente al
      cerrar el mes (o a mano desde el panel de Contabilidad).
    TXT
  end

  private

  def csv_entries(entries)
    CSV.generate do |csv|
      csv << %w[fecha hora categoria total base iva exencion comision_stripe tipo_cambio metodo referencia contrato cliente descripcion]
      entries.each do |e|
        csv << [e.entry_date, e.happened_at&.in_time_zone('America/Monterrey')&.strftime('%H:%M'),
                e.kind, e.amount.to_f, e.base_amount.to_f, e.iva_amount.to_f, e.extra_amount.to_f,
                e.stripe_fee.to_f, e.fx_rate&.to_f, e.method, e.reference, e.contract_label,
                e.client_name, e.description]
      end
    end
  end

  def csv_expenses(expenses)
    CSV.generate do |csv|
      csv << %w[fecha categoria monto proveedor metodo referencia contrato descripcion]
      expenses.each do |e|
        csv << [e.expense_date, e.category, e.amount.to_f, e.vendor, e.method, e.reference,
                e.contract_id, e.description]
      end
    end
  end

  def csv_pnl(sum)
    CSV.generate do |csv|
      csv << %w[concepto monto]
      LedgerEntry::INCOME.each { |k| csv << ["ingreso_#{k}_(sin_iva)", (sum[:kinds][k][:base] + sum[:kinds][k][:extra]).round(2)] }
      LedgerEntry::CONTRA.each { |k| csv << [k, (sum[:kinds][k][:base] + sum[:kinds][k][:extra]).round(2)] }
      csv << ['ajustes', sum[:adjust_total]]
      csv << ['ingreso_neto_sin_iva', sum[:revenue_net]]
      csv << ['iva_neto_cobrado_(pasivo)', sum[:iva_net]]
      csv << ['comisiones_stripe', -sum[:stripe_fees]]
      (sum[:expenses] || {}).each { |cat, amt| csv << ["gasto_#{cat}", -amt] }
      csv << ['gastos_total', -sum[:expenses_total]]
      csv << ['utilidad_neta', sum[:net_profit]]
    end
  end
end
