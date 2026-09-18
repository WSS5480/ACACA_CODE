# frozen_string_literal: true

module BankFeeds
  # CONCILIACIÓN con Stripe: copia los depósitos (payouts) de Stripe y los empareja
  # con el movimiento del banco que tiene el mismo importe y llega en la ventana de
  # días esperada (t−1 … t+5 alrededor de arrival_date). Un depósito solo se
  # empareja con UN movimiento y viceversa. Nunca borra ni modifica montos.
  class StripeReconciler
    DAYS_BACK   = 120
    WINDOW_PRE  = 1
    WINDOW_POST = 5

    def self.run!(days: DAYS_BACK)
      return 'Stripe no está configurado (STRIPE_SECRET_KEY)' unless StripeClient.configured?
      return 'Sin tabla' unless StripePayout.table_exists?

      n = refresh_payouts!(days: days)
      m = match!
      "#{n} depósitos revisados · #{m} emparejados"
    end

    # Depósitos de LAS DOS cuentas: EE. UU. (dólares) y México (pesos). Cada
    # uno se empareja después contra un movimiento del banco de su MISMA moneda
    # (la cuenta de México se lleva hoy como cuenta manual con su estado de cuenta).
    def self.refresh_payouts!(days: DAYS_BACK)
      StripeClient::ACCOUNTS.sum do |acct|
        next 0 unless StripeClient.configured?(acct)

        begin
          refresh_account_payouts!(acct, days: days)
        rescue StripeClient::Error => e
          Rails.logger.error "[StripeReconciler] cuenta #{acct}: #{e.message}"
          0
        end
      end
    end

    def self.refresh_account_payouts!(acct, days: DAYS_BACK)
      since = (Date.current - days).to_time.to_i
      starting_after = nil
      n = 0
      loop do
        params = { limit: 100, arrival_date: { gte: since } }
        params[:starting_after] = starting_after if starting_after
        res = StripeClient.request(:get, '/v1/payouts', params, account: acct)
        rows = res['data'] || []
        rows.each do |p|
          upsert_payout!(p, acct)
          n += 1
        end
        break unless res['has_more'] && rows.any?

        starting_after = rows.last['id']
      end
      n
    end

    def self.upsert_payout!(p, acct = 'us')
      sp = StripePayout.find_or_initialize_by(stripe_id: p['id'])
      dest = p['destination'].is_a?(Hash) ? p['destination']['id'] : p['destination']
      sp.assign_attributes(
        amount: (p['amount'].to_i / 100.0).round(2),
        currency: p['currency'].to_s.upcase.presence || 'USD',
        arrival_on: (p['arrival_date'] ? Time.at(p['arrival_date']).utc.to_date : nil),
        status: p['status'], description: (p['description'].presence || p['statement_descriptor'].presence),
        destination: dest, method: p['method'],
        raw: p.slice('id', 'amount', 'currency', 'arrival_date', 'created', 'status', 'description', 'statement_descriptor', 'method', 'type', 'automatic')
      )
      sp.account = acct if sp.respond_to?(:account=)
      sp.save!
      sp
    end

    def self.match!
      matched = 0
      StripePayout.unmatched.where(status: %w[paid in_transit pending]).where.not(arrival_on: nil).find_each do |sp|
        next unless sp.amount.to_f.positive?

        window = (sp.arrival_on - WINDOW_PRE)..(sp.arrival_on + WINDOW_POST)
        cands = BankTransaction.visible.where(stripe_payout_id: nil, currency: sp.currency, amount: sp.amount, posted_on: window).order(:posted_on).to_a
        tx = cands.detect { |t| t.description.to_s =~ /stripe/i } || (cands.size == 1 ? cands.first : nil)
        next unless tx

        tx.update_columns(stripe_payout_id: sp.stripe_id, updated_at: Time.current)
        sp.update_columns(bank_transaction_id: tx.id, matched_at: Time.current, updated_at: Time.current)
        matched += 1
      end
      matched
    end

    # Emparejar/desemparejar A MANO desde el admin (cuando el banco describe distinto).
    def self.link!(payout, tx)
      raise 'El movimiento ya está ligado a otro depósito' if tx.stripe_payout_id.present? && tx.stripe_payout_id != payout.stripe_id
      raise 'El depósito ya está ligado a otro movimiento' if payout.bank_transaction_id.present? && payout.bank_transaction_id != tx.id

      tx.update_columns(stripe_payout_id: payout.stripe_id, updated_at: Time.current)
      payout.update_columns(bank_transaction_id: tx.id, matched_at: Time.current, updated_at: Time.current)
    end

    def self.unlink!(payout)
      BankTransaction.where(stripe_payout_id: payout.stripe_id).update_all(stripe_payout_id: nil, updated_at: Time.current)
      payout.update_columns(bank_transaction_id: nil, matched_at: nil, updated_at: Time.current)
    end
  end
end
