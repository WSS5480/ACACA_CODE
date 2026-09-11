# frozen_string_literal: true

module BankFeeds
  # SINCRONIZACIÓN de conexiones bancarias. Idempotente: cada movimiento se
  # identifica por el id del banco/proveedor, así que correr de más nunca duplica.
  #   * El tick de 15 min llama run_due!: conexiones marcadas por webhook, nunca
  #     sincronizadas o con más de 20 h; una vez al día (full) todas.
  #   * "Actualizar ahora" en el admin llama sync! de una conexión.
  class Sync
    MAX_RESTARTS = 3

    def self.run_due!(full: false)
      out = {}
      return out unless BankConnection.table_exists?

      ran = false
      BankConnection.automatic.find_each do |c|
        next unless c.due_for_sync?(full: full)

        ran = true
        out["conn_#{c.id}"] = begin
          sync!(c)
        rescue StandardError => e
          e.message
        end
      end
      if (ran || full) && defined?(StripeReconciler)
        out[:stripe] = begin
          StripeReconciler.run!
        rescue StandardError => e
          e.message
        end
      end
      out
    end

    def self.sync!(conn)
      case conn.provider
      when 'plaid' then sync_plaid!(conn)
      else 'Cuenta manual: se alimenta importando el estado de cuenta.'
      end
    end

    # ---- Plaid: /transactions/sync con cursor (páginas hasta has_more=false) ----
    def self.sync_plaid!(conn)
      token = conn.access_token
      raise 'Sin token de acceso: vuelve a conectar el banco.' if token.blank?

      start_cursor = conn.sync_cursor.presence
      cursor = start_cursor
      restarts = 0
      added = modified = removed = 0
      status = nil
      begin
        loop do
          page = PlaidClient.sync(token, cursor)
          upsert_accounts!(conn, page['accounts']) if page['accounts'].present?
          index = account_index(conn)
          (page['added'] || []).each { |t| upsert_transaction!(conn, index, t) && (added += 1) }
          (page['modified'] || []).each { |t| upsert_transaction!(conn, index, t) && (modified += 1) }
          (page['removed'] || []).each { |r| removed += mark_removed!(conn, r) }
          status = page['transactions_update_status']
          cursor = page['next_cursor'].presence || cursor
          break unless page['has_more']
        end
      rescue PlaidClient::Error => e
        if e.mutation_during_pagination? && (restarts += 1) <= MAX_RESTARTS
          cursor = start_cursor
          retry
        end
        raise
      end

      # Si Plaid aún no terminó de bajar el historial, el siguiente tick reintenta.
      pending_history = status.present? && status != 'HISTORICAL_UPDATE_COMPLETE'
      conn.update_columns(sync_cursor: cursor, last_synced_at: Time.current, status: 'active', last_error: nil,
                          sync_requested_at: (pending_history ? Time.current : nil), updated_at: Time.current)
      "+#{added} ~#{modified} −#{removed}#{pending_history ? ' (historial en curso)' : ''}"
    rescue PlaidClient::Error => e
      # PRODUCT_NOT_READY: recién conectado, Plaid sigue bajando; no es un error de la conexión.
      if e.code == 'PRODUCT_NOT_READY'
        conn.update_columns(sync_requested_at: Time.current, updated_at: Time.current)
        return 'Plaid aún prepara el historial; se reintenta en el siguiente tick.'
      end
      conn.mark_error!(e.message, login_required: e.login_required?)
      raise
    end

    # Alta/actualización de cuentas con el payload de Plaid (/accounts/get o /transactions/sync).
    def self.upsert_accounts!(conn, accounts)
      Array(accounts).each do |a|
        acct = conn.bank_accounts.find_or_initialize_by(external_id: a['account_id'])
        bal = a['balances'] || {}
        acct.assign_attributes(
          name: a['name'], official_name: a['official_name'], mask: a['mask'],
          kind: a['type'], subtype: a['subtype'],
          currency: (bal['iso_currency_code'].presence || acct.currency.presence || 'USD'),
          current_balance: bal['current'], available_balance: bal['available'],
          balance_as_of: Time.current, active: true
        )
        acct.save!
      end
    end

    def self.account_index(conn)
      conn.bank_accounts.index_by(&:external_id)
    end

    def self.upsert_transaction!(conn, index, t)
      acct = index[t['account_id']]
      if acct.nil?
        # Cuenta que no venía en el payload: se da de alta mínima para no perder el movimiento.
        acct = conn.bank_accounts.create!(external_id: t['account_id'], name: 'Cuenta', currency: t['iso_currency_code'].presence || 'USD')
        index[acct.external_id] = acct
      end
      bt = BankTransaction.find_or_initialize_by(bank_account_id: acct.id, external_id: t['transaction_id'])
      bt.assign_attributes(
        posted_on: t['date'], authorized_on: t['authorized_date'],
        amount: (-t['amount'].to_f).round(2),                         # Plaid: positivo = sale; aquí: + entra / − sale
        currency: (t['iso_currency_code'].presence || acct.currency.presence || 'USD'),
        description: (t['original_description'].presence || t['name']).to_s.squish.truncate(255),
        merchant_name: t['merchant_name'].to_s.presence&.truncate(120),
        category: t.dig('personal_finance_category', 'primary'),
        category_detail: t.dig('personal_finance_category', 'detailed'),
        pending: t['pending'] ? true : false, pending_external_id: t['pending_transaction_id'],
        channel: t['payment_channel'], removed_at: nil,
        raw: t.slice('transaction_id', 'account_id', 'amount', 'iso_currency_code', 'date', 'authorized_date', 'name',
                     'original_description', 'merchant_name', 'pending', 'pending_transaction_id', 'payment_channel',
                     'personal_finance_category', 'counterparties')
      )
      bt.save!
      true
    end

    def self.mark_removed!(conn, r)
      ids = conn.bank_accounts.select(:id)
      BankTransaction.where(bank_account_id: ids, external_id: r['transaction_id']).update_all(removed_at: Time.current)
    end
  end
end
