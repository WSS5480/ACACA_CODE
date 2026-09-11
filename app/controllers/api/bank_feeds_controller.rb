# frozen_string_literal: true

module Api
  # BANCOS (solo master/admin/sistema): cuentas bancarias del negocio conectadas
  # al back office — saldos, movimientos, conciliación con los depósitos de Stripe,
  # gastos a un clic e importación de estados de cuenta.
  #
  # Seguridad:
  #   * Las credenciales del banco NUNCA pasan por aquí: la persona las escribe en
  #     la ventana de Plaid Link; el servidor solo intercambia un public_token.
  #   * El access_token de Plaid se guarda cifrado (BankConnection) y no se expone.
  #   * Desconectar exige escribir DESCONECTAR; los movimientos ya bajados se
  #     conservan (archivo), nunca se borran.
  #   * El webhook público lleva un token secreto en la URL y solo MARCA una
  #     conexión para sincronizar; los datos siempre se piden al proveedor.
  class BankFeedsController < ApplicationController
    include TokenAuthenticatable
    skip_before_action :authenticate_entity!, only: [:webhook], raise: false
    before_action :require_admin!, except: [:webhook]

    CONFIRM_DISCONNECT = 'DESCONECTAR'
    PER_MAX = 5000

    # GET /api/bank/summary
    def summary
      conns = BankConnection.order(:id).to_a
      totals = Hash.new(0.0)
      conns.each do |c|
        next if c.status == 'disconnected'

        c.bank_accounts.where(active: true).each do |a|
          next if a.current_balance.nil?

          totals[a.currency] += (a.credit? ? -1 : 1) * a.current_balance.to_f
        end
      end
      render json: {
        connections: conns.map(&:as_json_admin),
        totals: totals.transform_values { |v| v.round(2) },
        counts: { transactions: BankTransaction.visible.count,
                  unmatched_payouts: (StripePayout.table_exists? ? StripePayout.unmatched.where(status: 'paid').count : 0) },
        config: config_json
      }, status: :ok
    end

    # ---------------- Plaid (EE. UU.) ----------------

    # POST /api/bank/plaid/link_token { connection_id? }  → token para abrir Plaid Link
    # Con connection_id abre en MODO ACTUALIZACIÓN (re-login de una conexión existente).
    def plaid_link_token
      conn = params[:connection_id].present? ? BankConnection.find(params[:connection_id]) : nil
      res = BankFeeds::PlaidClient.link_token(client_user_id: "staff-#{@current_user.id}", webhook: webhook_url('plaid'),
                                              redirect_uri: admin_url, access_token: conn&.access_token)
      render json: { link_token: res['link_token'], expiration: res['expiration'], update_mode: conn.present?, connection_id: conn&.id }, status: :ok
    rescue BankFeeds::PlaidClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/plaid/exchange { public_token, institution: { institution_id, name } }
    def plaid_exchange
      ex = BankFeeds::PlaidClient.exchange(params[:public_token].to_s)
      inst = params[:institution].respond_to?(:to_unsafe_h) ? params[:institution].to_unsafe_h : {}
      conn = BankConnection.find_or_initialize_by(provider: 'plaid', external_id: ex['item_id'])
      conn.access_token = ex['access_token']
      conn.assign_attributes(institution_id: inst['institution_id'].presence || conn.institution_id,
                             institution_name: inst['name'].presence || conn.institution_name,
                             country: 'US', status: 'active', last_error: nil, disconnected_at: nil,
                             created_by_id: conn.created_by_id || @current_user.id)
      conn.save!
      if conn.institution_name.blank? && conn.institution_id.present?
        i = BankFeeds::PlaidClient.institution(conn.institution_id)
        conn.update_columns(institution_name: i['name']) if i && i['name'].present?
      end
      accts = BankFeeds::PlaidClient.accounts(conn.access_token)
      BankFeeds::Sync.upsert_accounts!(conn, accts['accounts'])
      first = begin
        BankFeeds::Sync.sync!(conn)
      rescue StandardError => e
        e.message
      end
      AuditLog.record!(actor: @current_user, action: 'bank_connected', target: conn, label: conn.label,
                       details: "#{conn.bank_accounts.count} cuenta(s) · Plaid #{BankFeeds::PlaidClient.env}")
      render json: { ok: true, connection: conn.reload.as_json_admin, first_sync: first }, status: :ok
    rescue BankFeeds::PlaidClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/plaid/relinked { connection_id }  — al terminar el modo actualización
    def plaid_relinked
      conn = BankConnection.find(params[:connection_id])
      conn.update_columns(status: 'active', last_error: nil, updated_at: Time.current)
      begin
        accts = BankFeeds::PlaidClient.accounts(conn.access_token)
        BankFeeds::Sync.upsert_accounts!(conn, accts['accounts'])
      rescue BankFeeds::PlaidClient::Error
        nil
      end
      res = begin
        BankFeeds::Sync.sync!(conn)
      rescue StandardError => e
        e.message
      end
      AuditLog.record!(actor: @current_user, action: 'bank_reconnected', target: conn, label: conn.label, details: res.to_s)
      render json: { ok: true, connection: conn.reload.as_json_admin, sync: res }, status: :ok
    end

    # ---------------- Cuentas manuales (cualquier banco; México hoy) ----------------

    # POST /api/bank/manual_accounts { institution_name, name, currency, country, mask, kind, current_balance }
    def create_manual_account
      country = params[:country].to_s.upcase
      currency = params[:currency].to_s.upcase
      conn = BankConnection.create!(provider: 'manual', external_id: "manual-#{SecureRandom.hex(6)}",
                                    institution_name: params[:institution_name].to_s.strip.presence || 'Banco',
                                    country: (%w[US MX].include?(country) ? country : 'MX'), status: 'active',
                                    created_by_id: @current_user.id)
      bal = params[:current_balance].presence && BankFeeds::StatementImport.parse_amount(params[:current_balance])
      conn.bank_accounts.create!(external_id: 'main', name: params[:name].to_s.strip.presence || 'Cuenta',
                                 mask: params[:mask].to_s.gsub(/\D/, '').last(4).presence,
                                 kind: (%w[depository credit].include?(params[:kind].to_s) ? params[:kind].to_s : 'depository'),
                                 subtype: params[:subtype].to_s.presence,
                                 currency: (%w[USD MXN].include?(currency) ? currency : 'MXN'),
                                 current_balance: bal, available_balance: bal, balance_as_of: (bal ? Time.current : nil))
      AuditLog.record!(actor: @current_user, action: 'bank_manual_account_created', target: conn, label: conn.label,
                       details: "#{params[:name]} · #{currency.presence || 'MXN'}")
      render json: { ok: true, connection: conn.reload.as_json_admin }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PUT /api/bank/accounts/:id { name, current_balance, active }
    def update_account
      acct = BankAccount.find(params[:id])
      attrs = {}
      attrs[:name] = params[:name].to_s.strip if params.key?(:name) && params[:name].to_s.strip.present?
      attrs[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)
      if params.key?(:current_balance)
        return render(json: { error: 'El saldo solo se captura a mano en cuentas manuales.' }, status: :unprocessable_entity) unless acct.bank_connection.manual?

        bal = BankFeeds::StatementImport.parse_amount(params[:current_balance])
        attrs.merge!(current_balance: bal, available_balance: bal, balance_as_of: Time.current)
      end
      acct.update!(attrs)
      render json: { ok: true, account: acct.reload.as_json_admin }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/accounts/:id/preview { csv }  → primeras filas para mapear columnas
    def preview_statement
      acct = BankAccount.find(params[:id])
      return render(json: { error: 'Solo las cuentas manuales importan estados de cuenta.' }, status: :unprocessable_entity) unless acct.bank_connection.manual?

      text = params[:csv].to_s
      return render(json: { error: 'Archivo vacío' }, status: :unprocessable_entity) if text.strip.empty?

      delimiter = BankFeeds::StatementImport.detect_delimiter(text)
      rows = BankFeeds::StatementImport.parse_rows(text, delimiter: delimiter)
      width = rows.map { |r| r&.size.to_i }.max.to_i
      render json: { delimiter: delimiter, total_rows: rows.size, columns: width, rows: rows.first(8).map { |r| Array(r).map(&:to_s) } }, status: :ok
    end

    # POST /api/bank/accounts/:id/import { csv, mapping: {date, description, amount | debit+credit, balance}, options: {header, date_format, negate, closing_balance} }
    def import_statement
      acct = BankAccount.find(params[:id])
      return render(json: { error: 'Solo las cuentas manuales importan estados de cuenta.' }, status: :unprocessable_entity) unless acct.bank_connection.manual?

      mapping = params[:mapping].respond_to?(:to_unsafe_h) ? params[:mapping].to_unsafe_h : {}
      options = params[:options].respond_to?(:to_unsafe_h) ? params[:options].to_unsafe_h : {}
      res = BankFeeds::StatementImport.run!(account: acct, csv_text: params[:csv].to_s, mapping: mapping, options: options, actor: @current_user)
      stripe = begin
        StripeClient.configured? ? BankFeeds::StripeReconciler.match! : nil
      rescue StandardError
        nil
      end
      render json: { ok: true, result: res.to_h, stripe_matched: stripe, account: acct.reload.as_json_admin }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # ---------------- Sincronización ----------------

    # POST /api/bank/connections/:id/sync
    def sync_connection
      conn = BankConnection.find(params[:id])
      return render(json: { error: 'Cuenta manual: importa el estado de cuenta para actualizarla.' }, status: :unprocessable_entity) if conn.manual?
      return render(json: { error: 'Conexión desconectada.' }, status: :unprocessable_entity) if conn.status == 'disconnected'

      res = BankFeeds::Sync.sync!(conn)
      stripe = begin
        StripeClient.configured? ? BankFeeds::StripeReconciler.run! : nil
      rescue StandardError => e
        e.message
      end
      render json: { ok: true, result: res, stripe: stripe, connection: conn.reload.as_json_admin }, status: :ok
    rescue StandardError => e
      render json: { error: e.message, connection: conn&.reload&.as_json_admin }, status: :unprocessable_entity
    end

    # POST /api/bank/sync_all
    def sync_all
      out = BankFeeds::Sync.run_due!(full: true)
      render json: { ok: true, result: out }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/connections/:id/disconnect { confirm: 'DESCONECTAR' }
    # Archivo, no borrado: la conexión queda 'disconnected', el token se destruye
    # (y se revoca en Plaid), las cuentas se marcan inactivas y los movimientos se conservan.
    def disconnect
      conn = BankConnection.find(params[:id])
      unless params[:confirm].to_s.strip.upcase == CONFIRM_DISCONNECT
        return render(json: { error: "Escribe #{CONFIRM_DISCONNECT} para confirmar." }, status: :unprocessable_entity)
      end

      provider_note = nil
      if conn.plaid? && conn.access_token.present?
        begin
          BankFeeds::PlaidClient.remove(conn.access_token)
          provider_note = 'acceso revocado en Plaid'
        rescue BankFeeds::PlaidClient::Error => e
          provider_note = "no se pudo revocar en Plaid: #{e.message}"
        end
      end
      conn.access_token = nil
      conn.status = 'disconnected'
      conn.disconnected_at = Time.current
      conn.save!(validate: false)
      conn.bank_accounts.update_all(active: false, updated_at: Time.current)
      AuditLog.record!(actor: @current_user, action: 'bank_disconnected', target: conn, label: conn.label,
                       details: ['movimientos conservados', provider_note].compact.join(' · '))
      render json: { ok: true, connection: conn.reload.as_json_admin, note: provider_note }, status: :ok
    end

    # ---------------- Movimientos ----------------

    # GET /api/bank/transactions?account_id&connection_id&q&from&to&kind=in|out&only=stripe|sin_gasto|con_gasto|pending&page&per
    def transactions
      scope = BankTransaction.visible.joins(bank_account: :bank_connection)
      scope = scope.where(bank_account_id: params[:account_id]) if params[:account_id].present?
      scope = scope.where(bank_accounts: { bank_connection_id: params[:connection_id] }) if params[:connection_id].present?
      unless params[:from].to_s == 'all'
        from = parse_date(params[:from]) || (Date.current - 90)
        to   = parse_date(params[:to]) || Date.current
        to = from if to < from
        scope = scope.where(posted_on: from..to)
      end
      if params[:q].present?
        q = params[:q].to_s.strip
        num = BankFeeds::StatementImport.parse_amount(q)
        scope = if num && q =~ /\A[-$\d.,\s]+\z/
                  scope.where('bank_transactions.amount = ? OR bank_transactions.amount = ?', num.abs, -num.abs)
                else
                  like = "%#{q}%"
                  scope.where('bank_transactions.description ILIKE ? OR bank_transactions.merchant_name ILIKE ? OR bank_transactions.stripe_payout_id ILIKE ?', like, like, like)
                end
      end
      scope = scope.where('bank_transactions.amount > 0') if params[:kind] == 'in'
      scope = scope.where('bank_transactions.amount < 0') if params[:kind] == 'out'
      case params[:only]
      when 'stripe'    then scope = scope.where.not(stripe_payout_id: nil)
      when 'sin_gasto' then scope = scope.where('bank_transactions.amount < 0').where(expense_id: nil)
      when 'con_gasto' then scope = scope.where.not(expense_id: nil)
      when 'pending'   then scope = scope.where(pending: true)
      end
      per = [[params[:per].to_i, 1].max, PER_MAX].min
      per = 100 if params[:per].blank?
      page = [params[:page].to_i, 1].max
      total = scope.count
      sums = scope.group('bank_transactions.currency').pluck(Arel.sql("bank_transactions.currency, SUM(CASE WHEN bank_transactions.amount > 0 THEN bank_transactions.amount ELSE 0 END), SUM(CASE WHEN bank_transactions.amount < 0 THEN bank_transactions.amount ELSE 0 END)"))
      rows = scope.preload(bank_account: :bank_connection).order(posted_on: :desc, id: :desc).offset((page - 1) * per).limit(per)
      render json: { transactions: rows.map(&:as_json_admin), total: total, page: page, per: per,
                     sums: sums.map { |cur, inn, out| { currency: cur, in: inn.to_f.round(2), out: out.to_f.round(2) } } }, status: :ok
    end

    # POST /api/bank/transactions/:id/expense { category, description, vendor, contract_id, amount }
    # Convierte un CARGO del banco en un Gasto del libro (una sola vez). MXN se
    # convierte a USD con el tipo de cambio vigente en la fecha del movimiento.
    def create_expense_from_transaction
      tx = BankTransaction.find(params[:id])
      return render(json: { error: "Este movimiento ya tiene el gasto ##{tx.expense_id}." }, status: :unprocessable_entity) if tx.expense_id.present?
      return render(json: { error: 'Solo los cargos (salidas de dinero) se registran como gasto.' }, status: :unprocessable_entity) unless tx.outflow?

      category = Expense::CATEGORIES.include?(params[:category].to_s) ? params[:category].to_s : tx.suggested_expense_category
      amount = tx.amount.abs.to_f.round(2)
      fx_note = nil
      if tx.currency.to_s.upcase != 'USD'
        rate = BankFeeds.usd_to_mxn_on(tx.posted_on)
        return render(json: { error: 'No hay tipo de cambio registrado para convertir a USD (Catálogo y precios → Tipo de cambio).' }, status: :unprocessable_entity) if rate.nil? || tx.currency.to_s.upcase != 'MXN'

        fx_note = "#{format('%.2f', amount)} MXN @ #{format('%.4f', rate)}"
        amount = (amount / rate).round(2)
      end
      amount = params[:amount].to_f.round(2) if params[:amount].present? && params[:amount].to_f.positive?
      desc = [params[:description].to_s.strip.presence || tx.merchant_name.presence || tx.description, fx_note].compact.join(' · ').truncate(255)
      e = Expense.create!(expense_date: tx.posted_on, category: category, description: desc,
                          vendor: (params[:vendor].to_s.strip.presence || tx.merchant_name.presence),
                          amount: amount, method: 'banco', reference: "bank:#{tx.id}",
                          contract_id: params[:contract_id].presence, created_by_id: @current_user.id)
      tx.update_columns(expense_id: e.id, updated_at: Time.current)
      AuditLog.record!(actor: @current_user, action: 'expense_added', target: e,
                       label: "#{e.category} $#{format('%.2f', e.amount)}",
                       details: "desde movimiento bancario ##{tx.id} · #{tx.bank_account.bank_connection.label} · #{tx.description}")
      render json: { ok: true, expense: { id: e.id, expense_date: e.expense_date.to_s, category: e.category, amount: e.amount.to_f, description: e.description },
                     transaction: tx.reload.as_json_admin }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # ---------------- Conciliación Stripe ----------------

    # GET /api/bank/stripe/payouts?days=120&only=unmatched
    def stripe_payouts
      days = [[params[:days].to_i, 7].max, 400].min
      days = 120 if params[:days].blank?
      scope = StripePayout.where('arrival_on >= ?', Date.current - days).or(StripePayout.where(arrival_on: nil))
      scope = scope.unmatched if params[:only] == 'unmatched'
      rows = scope.order(arrival_on: :desc, id: :desc).limit(500)
      render json: { payouts: rows.map(&:as_json_admin), stripe_configured: StripeClient.configured?,
                     unmatched: StripePayout.unmatched.where(status: 'paid').count }, status: :ok
    end

    # POST /api/bank/stripe/reconcile
    def stripe_reconcile
      render json: { ok: true, result: BankFeeds::StripeReconciler.run! }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/stripe/payouts/:id/link { transaction_id }
    def stripe_link
      sp = StripePayout.find(params[:id])
      tx = BankTransaction.find(params[:transaction_id])
      BankFeeds::StripeReconciler.link!(sp, tx)
      render json: { ok: true, payout: sp.reload.as_json_admin }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/bank/stripe/payouts/:id/unlink
    def stripe_unlink
      sp = StripePayout.find(params[:id])
      BankFeeds::StripeReconciler.unlink!(sp)
      render json: { ok: true, payout: sp.reload.as_json_admin }, status: :ok
    end

    # ---------------- Webhook (público, con token secreto en la URL) ----------------

    # POST /api/bank/webhooks/:provider/:token
    def webhook
      return head(:not_found) unless ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, BankFeeds.webhook_token)

      payload = begin
        JSON.parse(request.raw_post.to_s)
      rescue StandardError
        {}
      end
      if params[:provider] == 'plaid'
        conn = BankConnection.find_by(provider: 'plaid', external_id: payload['item_id'].to_s)
        if conn && conn.status != 'disconnected'
          type = payload['webhook_type'].to_s
          code = payload['webhook_code'].to_s
          if type == 'ITEM'
            case code
            when 'ERROR'
              err = payload['error'] || {}
              conn.mark_error!(err['error_message'].presence || err['error_code'].presence || 'Error reportado por Plaid',
                               login_required: err['error_code'] == 'ITEM_LOGIN_REQUIRED')
            when 'USER_PERMISSION_REVOKED', 'USER_ACCOUNT_REVOKED'
              conn.mark_error!('El banco revocó el permiso: vuelve a conectar la cuenta.', login_required: true)
            when 'PENDING_EXPIRATION', 'PENDING_DISCONNECT'
              conn.update_columns(meta: (conn.meta || {}).merge('pending_expiration' => payload['consent_expiration_time'] || Time.current.iso8601), updated_at: Time.current)
            when 'LOGIN_REPAIRED'
              conn.update_columns(status: 'active', last_error: nil, sync_requested_at: Time.current, updated_at: Time.current)
            end
          else
            conn.request_sync! # TRANSACTIONS: SYNC_UPDATES_AVAILABLE, INITIAL_UPDATE, HISTORICAL_UPDATE, DEFAULT_UPDATE…
          end
        end
      end
      head :ok
    end

    private

    def require_admin!
      return if %w[master admin sistema].include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end

    def admin_url
      "#{request.base_url}/admin.html"
    end

    def webhook_url(provider)
      "#{request.base_url}/api/bank/webhooks/#{provider}/#{BankFeeds.webhook_token}"
    end

    def config_json
      { plaid: { configured: BankFeeds::PlaidClient.configured?, env: BankFeeds::PlaidClient.env },
        stripe: { configured: StripeClient.configured? },
        redirect_uri: admin_url, plaid_webhook_url: webhook_url('plaid') }
    end

    def parse_date(v)
      Date.parse(v.to_s)
    rescue StandardError
      nil
    end
  end
end
