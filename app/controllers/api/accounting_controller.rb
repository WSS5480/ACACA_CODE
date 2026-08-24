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

    # ---- ANULAR / MODIFICAR PAGOS ----
    # POST /api/accounting/void_payment { payment_id, refund, reason }
    # ANULA un pago: contra-asiento en el libro (reembolso o ajuste), reembolso
    # Stripe opcional a la forma de pago original, y el contrato se RECONSTRUYE
    # sin ese pago (calendario, saldo, crédito y estatus). Bitácora siempre.
    def void_payment
      p = Payment.find(params[:payment_id])
      contract = p.contract
      reason = params[:reason].to_s.strip
      do_refund = ActiveModel::Type::Boolean.new.cast(params[:refund])
      total_paid = (p.try(:total_charged).to_f.positive? ? p.total_charged.to_f : p.amount.to_f).round(2)

      refund_note = nil
      if do_refund
        pi_raw = p.respond_to?(:stripe_payment_intent_id) ? p.stripe_payment_intent_id.to_s : ''
        if pi_raw.present?
          multi = pi_raw.match(/\A(pi_[A-Za-z0-9]+)-c\d+\z/)
          pi_id = multi ? multi[1] : pi_raw
          if multi
            cents = (total_paid * 100).round
            StripeClient.request(:post, '/v1/refunds', { payment_intent: pi_id, amount: cents })
            refund_note = "Stripe: reembolsados $#{format('%.2f', total_paid)} (parcial de #{pi_id})"
          else
            StripeClient.request(:post, '/v1/refunds', { payment_intent: pi_id })
            refund_note = "Stripe: reembolso COMPLETO de #{pi_id}"
          end
        else
          refund_note = "Pago manual (#{p.method.presence || 'sin método'}): devolver $#{format('%.2f', total_paid)} a mano"
        end
      end

      LedgerEntry.record_refund!(
        contract: contract, payment: p, total: total_paid,
        reference: (p.respond_to?(:stripe_payment_intent_id) && p.stripe_payment_intent_id.presence) || "pago ##{p.id}",
        by: @current_user, kind: (do_refund ? 'reembolso' : 'ajuste'),
        description: "#{do_refund ? 'Reembolso y anulación' : 'ANULACIÓN (sin reembolso)'} del pago ##{p.id}#{reason.present? ? " · #{reason}" : ''}"
      )
      remove_and_replay!(contract, p)
      AuditLog.record!(actor: @current_user, action: 'payment_voided', target: contract,
                       label: contract ? (contract.contract_number.presence || contract.order_ref) : "pago ##{params[:payment_id]}",
                       details: "Anuló pago de $#{format('%.2f', total_paid)}#{do_refund ? ' CON reembolso' : ' sin reembolso'}#{reason.present? ? " · #{reason}" : ''}#{refund_note ? " · #{refund_note}" : ''}")
      render json: { ok: true, refund: refund_note, balance: contract&.balance }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Pago no encontrado (¿ya fue anulado?)' }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/accounting/modify_payment { payment_id, amount, extra_amount, iva_amount, paid_at, reason }
    # CORRECCIÓN contable: contra-asiento del pago original + pago corregido.
    # NO toca el cobro en Stripe — corrige el registro y el contrato.
    def modify_payment
      p = Payment.find(params[:payment_id])
      contract = p.contract
      return render(json: { error: 'El pago no tiene contrato.' }, status: :unprocessable_entity) unless contract

      new_base = params[:amount].to_f.round(2)
      return render(json: { error: 'El abono debe ser mayor a cero.' }, status: :unprocessable_entity) if new_base <= 0

      new_extra = params[:extra_amount].to_f.round(2)
      new_iva = params[:iva_amount].to_f.round(2)
      reason = params[:reason].to_s.strip
      paid_at = begin
        Time.zone.parse(params[:paid_at].to_s)
      rescue StandardError
        nil
      end
      paid_at ||= p.paid_at

      old_total = (p.try(:total_charged).to_f.positive? ? p.total_charged.to_f : p.amount.to_f).round(2)
      old_desc = "pago ##{p.id} ($#{format('%.2f', old_total)})"
      keep = { method: p.method, user_id: p.user_id,
               kind: p.try(:kind).presence,
               stripe_ref: (p.respond_to?(:stripe_payment_intent_id) ? p.stripe_payment_intent_id : nil),
               note: p.note.to_s }

      # 1) contra-asiento del original (el libro nunca se edita, se compensa)
      LedgerEntry.record_refund!(
        contract: contract, payment: p, total: old_total,
        reference: keep[:stripe_ref].presence || "pago ##{p.id}",
        by: @current_user, kind: 'ajuste',
        description: "Corrección: reverso del #{old_desc}#{reason.present? ? " · #{reason}" : ''}"
      )
      # 2) quitar el pago y reconstruir el contrato con los demás pagos
      remove_and_replay!(contract, p)
      # 3) pago corregido (su hook lo asienta en el libro con folio nuevo)
      np = contract.payments.new(amount: new_base, method: keep[:method], paid_at: paid_at, user_id: keep[:user_id],
                                 note: "CORREGIDO (antes #{old_desc}) | #{keep[:note]}".truncate(250))
      np.kind = keep[:kind] if keep[:kind].present? && np.respond_to?(:kind=)
      np.stripe_payment_intent_id = keep[:stripe_ref] if keep[:stripe_ref].present?
      if Payment.column_names.include?('iva_amount')
        np.iva_amount = new_iva
        np.extra_amount = new_extra
        np.total_charged = (new_base + new_extra + new_iva).round(2)
      end
      np.save!
      AuditLog.record!(actor: @current_user, action: 'payment_modified', target: contract,
                       label: contract.contract_number.presence || contract.order_ref,
                       details: "Corrigió #{old_desc} → base $#{format('%.2f', new_base)} + exención $#{format('%.2f', new_extra)} + IVA $#{format('%.2f', new_iva)}#{reason.present? ? " · #{reason}" : ''}")
      render json: { ok: true, payment_id: np.id, balance: contract.reload.balance }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Pago no encontrado (¿ya fue anulado?)' }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # Quita un pago y RECONSTRUYE el contrato con los pagos restantes:
    # calendario desde cero, pagos re-aplicados en orden, crédito re-consumido
    # y estatus recalculado. Es la única forma segura de "des-aplicar" un pago.
    def remove_and_replay!(contract, payment)
      amt = payment.amount.to_f
      remaining = contract ? contract.payments.where.not(id: payment.id).order(:paid_at, :id).pluck(:amount).map(&:to_f) : []
      payment.destroy!
      return unless contract

      contract.update_columns(status: 'active') if contract.status == 'paid'
      contract.build_amortization!
      remaining.each { |a| contract.apply_payment!(a) }
      contract.update!(status: 'paid') if contract.paid_off? && contract.status != 'cancelled'
      cr = contract.user&.credit
      if cr
        limit = ((cr.respond_to?(:credit_limit) ? cr.credit_limit : nil) || cr.amount).to_f
        cr.update_column(:amount, [[cr.amount.to_f - amt, 0].max, limit].min.round(2))
      end
      contract.reload
    end

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
        contract_label: e.contract_label, client_name: e.client_name, contract_id: e.contract_id,
        payment_id: e.payment_id,
        items_label: e.try(:items_label), waiver_pct: e.try(:waiver_pct)&.to_f, payment_seq: e.try(:payment_seq) }
    end

    def expense_json(e)
      { id: e.id, expense_date: e.expense_date.to_s, category: e.category, description: e.description,
        vendor: e.vendor, amount: e.amount.to_f, method: e.method, reference: e.reference,
        contract_id: e.contract_id }
    end
  end
end
