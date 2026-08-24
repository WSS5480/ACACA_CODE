# frozen_string_literal: true

# CORTE CONTABLE: fotografía inmutable de un periodo (diario o mensual).
# El corte diario corre solo justo después de medianoche (Monterrey) y el
# mensual el día 1 con el mes anterior completo. Un pago capturado tarde
# aparece en el corte del día en que se capturó — el corte cerrado no cambia.
class AccountingClose < ApplicationRecord
  PERIODS = %w[daily monthly].freeze
  validates :period_type, inclusion: { in: PERIODS }
  validates :period_date, uniqueness: { scope: :period_type }

  # Resumen de un rango: totales por categoría, IVA, comisiones Stripe, gastos
  # y utilidad neta. La utilidad usa montos SIN IVA (el IVA es un pasivo, no ingreso).
  def self.summarize(from, to)
    entries = LedgerEntry.where(entry_date: from..to)
    kinds = {}
    LedgerEntry::KINDS.each do |k|
      rows = entries.where(kind: k)
      kinds[k] = { count: rows.count,
                   total: rows.sum(:amount).to_f.round(2),
                   base: rows.sum(:base_amount).to_f.round(2),
                   iva: rows.sum(:iva_amount).to_f.round(2),
                   extra: rows.sum(:extra_amount).to_f.round(2) }
    end
    income = LedgerEntry::INCOME.sum { |k| kinds[k][:total] }.round(2)
    contra = LedgerEntry::CONTRA.sum { |k| kinds[k][:total] }.round(2)
    adjust = kinds['ajuste'][:total]
    fees   = entries.sum(:stripe_fee).to_f.round(2)

    exp_scope = Expense.where(expense_date: from..to)
    expenses = exp_scope.group(:category).sum(:amount).transform_values { |v| v.to_f.round(2) }
    expenses_total = exp_scope.sum(:amount).to_f.round(2)

    # Ingreso neto (sin IVA): base + exención de ingresos, menos base + exención de contra-ingresos.
    revenue_net = (LedgerEntry::INCOME + LedgerEntry::CONTRA)
                  .sum { |k| kinds[k][:base] + kinds[k][:extra] }.round(2)

    {
      from: from.to_s, to: to.to_s, entry_count: entries.count,
      kinds: kinds,
      income_total: income,                       # cobrado (con IVA)
      contra_total: contra,                       # reembolsos + contracargos (negativo)
      adjust_total: adjust.round(2),
      deposit_net: (income + contra + adjust).round(2), # lo que entra/sale en total
      iva_net: entries.sum(:iva_amount).to_f.round(2),  # IVA cobrado − IVA devuelto
      stripe_fees: fees,
      expenses: expenses, expenses_total: expenses_total,
      revenue_net: revenue_net,
      net_profit: (revenue_net + adjust - fees - expenses_total).round(2)
    }
  end

  # Corte DIARIO. Si ya existe no se toca (inmutable) salvo force: true (queda en bitácora).
  def self.run_daily!(date, by: nil, force: false)
    existing = find_by(period_type: 'daily', period_date: date)
    return existing if existing && !force

    data = summarize(date, date)
    if existing
      existing.update!(data: data, run_at: Time.current, run_by_id: by&.id)
      existing
    else
      create!(period_type: 'daily', period_date: date, data: data, run_at: Time.current, run_by_id: by&.id)
    end
  end

  # Corte MENSUAL: resume el mes y verifica que cuadre con la suma de los cortes diarios.
  def self.run_monthly!(month_start, by: nil, force: false)
    from = month_start.to_date.beginning_of_month
    to   = month_start.to_date.end_of_month
    existing = find_by(period_type: 'monthly', period_date: from)
    return existing if existing && !force

    data = summarize(from, to)
    dailies = where(period_type: 'daily', period_date: from..to)
    daily_sum = dailies.sum { |d| d.data['deposit_net'].to_f }.round(2)
    data[:daily_closes] = dailies.count
    data[:daily_sum] = daily_sum
    data[:daily_diff] = (data[:deposit_net] - daily_sum).round(2) # ≠0 = pagos capturados tarde o cortes faltantes

    if existing
      existing.update!(data: data, run_at: Time.current, run_by_id: by&.id)
      existing
    else
      create!(period_type: 'monthly', period_date: from, data: data, run_at: Time.current, run_by_id: by&.id)
    end
  end
end
