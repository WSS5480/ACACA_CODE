# frozen_string_literal: true

module Api
  # CONTABILIDAD (solo master/admin/sistema): registro de transacciones, estado
  # de resultados, gastos, movimientos manuales (reembolso/contracargo/ajuste),
  # cortes diario/mensual y paquete mensual para el contador.
  class AccountingController < ApplicationController
    include TokenAuthenticatable
    before_action :authenticate_entity!
    before_action :require_admin!

    # GET /api/accounting/register?from&to&kind
    def register
      from, to = range_params
      scope = LedgerEntry.where(entry_date: from..to).order(happened_at: :desc, id: :desc)
      scope = scope.where(kind: params[:kind]) if params[:kind].present? && LedgerEntry::KINDS.include?(params[:kind])
      render json: { entries: scope.limit(2000).map { |e| entry_json(e) },
                     summary: AccountingClose.summarize(from, to) }, status: :ok
    end

    # GET /api/accounting/pnl?from&to  -> estado de resultados del rango
    def pnl
      from, to = range_params
      render json: { pnl: AccountingClose.summarize(from, to) }, status: :ok
    end

    # GET /api/accounting/closes?period_type=daily|monthly
    def closes
      pt = %w[daily monthly].include?(params[:period_type].to_s) ? params[:period_type].to_s : 'daily'
      rows = AccountingClose.where(period_type: pt).order(period_date: :desc).limit(120)
      render json: { closes: rows.map { |c| { id: c.id, period_type: c.period_type, period_date: c.period_date.to_s, run_at: c.run_at, data: c.data } } }, status: :ok
    end

    # POST /api/accounting/run_close { period_type, date, force }
    # Corre un corte a mano. force=1 (solo master) RE-corre uno ya cerrado y queda en bitácora.
    def run_close
      pt = params[:period_type].to_s
      return render(json: { error: 'Tipo inválido' }, status: :unprocessable_entity) unless %w[daily monthly].include?(pt)

      date = begin
        Date.parse(params[:date].to_s)
      rescue StandardError
        nil
      end
      return render(json: { error: 'Fecha inválida' }, status: :unprocessable_entity) unless date

      force = ActiveModel::Type::Boolean.new.cast(params[:force])
      if force && @current_user&.role&.name != 'master'
        return render(json: { error: 'Solo master puede RE-correr un corte cerrado.' }, status: :forbidden)
      end

      close = pt == 'monthly' ? AccountingClose.run_monthly!(date, by: @current_user, force: force)
                              : AccountingClose.run_daily!(date, by: @current_user, force: force)
      AuditLog.record!(actor: @current_user, action: 'accounting_close_run',
                       label: "#{pt == 'monthly' ? 'mensual' : 'diario'} #{date}",
                       details: force ? '⚠ RE-corrido (force)' : 'corrido a mano')
      render json: { ok: true, close: { period_type: close.period_type, period_date: close.period_date.to_s, data: close.data } }, status: :ok
    end

    # ---- GASTOS ----
    # GET /api/accounting/expenses?from&to
    def expenses
      from, to = range_params
      rows = Expense.where(expense_date: from..to).order(expense_date: :desc, id: :desc).limit(1000)
      render json: { expenses: rows.map { |e| expense_json(e) },
                     total: rows.sum(:amount).to_f.round(2) }, status: :ok
    end

    # POST /api/accounting/expenses
    def create_expense
      e = Expense.new(params.permit(:expense_date, :category, :description, :vendor, :amount, :method, :reference, :contract_id))
      e.expense_date = Date.current if e.expense_date.blank?
      e.created_by_id = @current_user.id
      e.save!
      AuditLog.record!(actor: @current_user, action: 'expense_added', target: e,
                       label: "#{e.category} $#{format('%.2f', e.amount)}",
                       details: [e.description, e.vendor].compact.join(' · '))
      render json: { ok: true, expense: expense_json(e) }, status: :ok
    rescue ActiveRecord::RecordInvalid => err
      render json: { error: err.message }, status: :unprocessable_entity
    end

    # DELETE /api/accounting/expenses/:id (solo master)
    def delete_expense
      return render(json: { error: 'Solo master puede eliminar gastos.' }, status: :forbidden) unless @current_user&.role&.name == 'master'

      e = Expense.find(params[:id])
      AuditLog.record!(actor: @current_user, action: 'expense_deleted', target: e,
                       label: "#{e.category} $#{format('%.2f', e.amount)}", details: e.description)
      e.destroy!
      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Gasto no encontrado' }, status: :not_found
    end

    # ---- MOVIMIENTOS MANUALES ----
    # POST /api/accounting/entry { kind: reembolso|contracargo|ajuste, amount, contract_id?,
    #                              iva_amount?, reference?, description?, date?, dispute_fee? }
    # reembolso/contracargo entran NEGATIVOS; ajuste conserva el signo capturado.
    # contracargo con dispute_fee > 0 registra además la cuota de disputa como gasto (comisiones).
    def create_entry
      kind = params[:kind].to_s
      return render(json: { error: 'Tipo inválido' }, status: :unprocessable_entity) unless %w[reembolso contracargo ajuste].include?(kind)

      amt = params[:amount].to_f.round(2)
      return render(json: { error: 'Monto inválido' }, status: :unprocessable_entity) if amt.zero?

      signed = kind == 'ajuste' ? amt : -amt.abs
      iva = params[:iva_amount].to_f.round(2)
      iva = -iva.abs if signed.negative? && iva.positive?
      contract = Contract.find_by(id: params[:contract_id]) if params[:contract_id].present?
      date = begin
        Date.parse(params[:date].to_s)
      rescue StandardError
        Date.current
      end
      u = contract&.user
      entry = LedgerEntry.create!(
        entry_date: date, happened_at: Time.current, kind: kind,
        amount: signed, base_amount: (signed - iva).round(2), iva_amount: iva,
        method: params[:method].presence || 'manual',
        reference: params[:reference].presence || "manual-#{kind}",
        description: params[:description].presence,
        contract_label: contract ? (contract.contract_number.presence || contract.order_ref) : nil,
        client_name: [u&.name, u&.last_name].compact.join(' ').presence,
        contract_id: contract&.id, user_id: u&.id, created_by_id: @current_user.id
      )
      fee = params[:dispute_fee].to_f.round(2)
      if kind == 'contracargo' && fee.positive?
        Expense.create!(expense_date: date, category: 'comisiones', amount: fee,
                        description: "Cuota por contracargo #{entry.reference}",
                        contract_id: contract&.id, created_by_id: @current_user.id)
      end
      AuditLog.record!(actor: @current_user, action: 'accounting_entry_added', target: entry,
                       label: "#{kind} $#{format('%.2f', signed)}",
                       details: [entry.contract_label, params[:description].presence].compact.join(' · '))
      render json: { ok: true, entry: entry_json(entry) }, status: :ok
    rescue ActiveRecord::RecordInvalid => err
      render json: { error: err.message }, status: :unprocessable_entity
    end

    # ---- CONFIGURACIÓN / PAQUETE DEL CONTADOR ----
    def settings
      render json: { accounting_email: AppSetting.get('accounting_email').to_s }, status: :ok
    end

    def update_settings
      AppSetting.set('accounting_email', params[:accounting_email].to_s.strip)
      AuditLog.record!(actor: @current_user, action: 'accounting_settings_changed',
                       label: 'correo del contador', details: params[:accounting_email].to_s.strip)
      render json: { ok: true }, status: :ok
    end

    # POST /api/accounting/send_package { month: 'YYYY-MM-01' }  (default: mes anterior)
    def send_package
      email = AppSetting.get('accounting_email').to_s
      return render(json: { error: 'Primero configura el correo del contador.' }, status: :unprocessable_entity) if email.blank?

      month = begin
        Date.parse(params[:month].to_s).beginning_of_month
      rescue StandardError
        Date.current.prev_month.beginning_of_month
      end
      AccountingMailer.monthly_package(month).deliver_now
      render json: { ok: true, sent_to: email, month: month.strftime('%Y-%m') }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_admin!
      return if %w[master admin sistema].include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end

    def range_params
      from = begin
        Date.parse(params[:from].to_s)
      rescue StandardError
        Date.current.beginning_of_month
      end
      to = begin
        Date.parse(params[:to].to_s)
      rescue StandardError
        Date.current
      end
      to = from if to < from
      [from, to]
    end

    def entry_json(e)
      { id: e.id, entry_date: e.entry_date.to_s, happened_at: e.happened_at, kind: e.kind,
        amount: e.amount.to_f, base_amount: e.base_amount.to_f, iva_amount: e.iva_amount.to_f,
        extra_amount: e.extra_amount.to_f, stripe_fee: e.stripe_fee.to_f, fx_rate: e.fx_rate&.to_f,
        method: e.method, reference: e.reference, description: e.description,
        contract_label: e.contract_label, client_name: e.client_name, contract_id: e.contract_id }
    end

    def expense_json(e)
      { id: e.id, expense_date: e.expense_date.to_s, category: e.category, description: e.description,
        vendor: e.vendor, amount: e.amount.to_f, method: e.method, reference: e.reference,
        contract_id: e.contract_id }
    end
  end
end
