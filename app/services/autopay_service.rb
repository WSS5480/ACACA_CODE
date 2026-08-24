# frozen_string_literal: true

# Cobro automatico de cuotas vencidas/del dia con la tarjeta guardada en Stripe.
# Ejecutar diario (Render Cron Job):  bundle exec rails runner "AutopayService.run"
class AutopayService
  def self.run
    return { ok: false, error: 'Stripe no configurado' } unless StripeClient.configured?

    charged = 0
    skipped = 0
    failed = 0

    Contract.where(autopay: true, status: 'active').includes(:user, :orders).find_each do |contract|
      result = charge_contract(contract)
      case result
      when :charged then charged += 1
      when :skipped then skipped += 1
      else failed += 1
      end
    end

    summary = { ok: true, charged: charged, skipped: skipped, failed: failed, at: Time.current }
    Rails.logger.info "[Autopay] #{summary.inspect}"
    summary
  end

  # Cobra lo vencido + lo que vence HOY de un contrato. :charged / :skipped / :failed
  def self.charge_contract(contract)
    user = contract.user
    return :skipped unless user&.stripe_customer_id.present?

    due = contract.contract_installments.where.not(status: 'paid')
                  .where('due_date <= ?', Date.current)
                  .sum { |i| (i.amount.to_f - i.paid_amount.to_f) }.round(2)
    return :skipped if due <= 0.009

    waiver_pct = contract.orders.first&.waiver.to_f
    fee = waiver_pct > 0 ? (due * waiver_pct / 100.0).round(2) : 0.0

    pms = StripeClient.request(:get, '/v1/payment_methods', { customer: user.stripe_customer_id, type: 'card' })
    pm = pms.dig('data', 0, 'id')
    return :skipped if pm.blank?

    pi = StripeClient.request(:post, '/v1/payment_intents', {
      amount: ((due + fee) * 100).round,
      currency: 'usd',
      customer: user.stripe_customer_id,
      payment_method: pm,
      off_session: 'true',
      confirm: 'true',
      description: "Autopay contrato #{contract.contract_number}",
      metadata: { contract_id: contract.id, user_id: user.id, base_amount: due, waiver_fee: fee, kind: 'autopay' }
    })

    if pi['status'] == 'succeeded'
      unless Payment.exists?(stripe_payment_intent_id: pi['id'])
        note = "Autopay Stripe #{pi['id']}"
        note += " | exención de responsabilidad $#{'%.2f' % fee}" if fee > 0
        attrs = { amount: due, method: 'autopay', note: note, stripe_payment_intent_id: pi['id'] }
        # Desglose contable (autopay no cobra IVA hoy: base + exención).
        if Payment.column_names.include?('extra_amount')
          attrs[:extra_amount] = fee
          attrs[:total_charged] = (due + fee).round(2)
          attrs[:stripe_fee] = stripe_fee_for(pi)
        end
        contract.payments.create!(attrs)
      end
      contract.update_column(:autopay_last_error, nil)
      :charged
    else
      contract.update_column(:autopay_last_error, "Estado #{pi['status']} #{Time.current.strftime('%Y-%m-%d')}")
      :failed
    end
  rescue StripeClient::Error => e
    contract.update_column(:autopay_last_error, "#{e.message.to_s.truncate(120)} #{Time.current.strftime('%Y-%m-%d')}")
    Rails.logger.error "[Autopay] contrato #{contract.id}: #{e.message}"
    :failed
  rescue StandardError => e
    Rails.logger.error "[Autopay] contrato #{contract.id}: #{e.class} #{e.message}"
    :failed
  end

  # Comisión de Stripe del cargo (misma consulta que en StripeController). Nunca bloquea.
  def self.stripe_fee_for(pi)
    ch_id = pi['latest_charge']
    ch_id = ch_id['id'] if ch_id.is_a?(Hash)
    return nil if ch_id.blank?

    ch = StripeClient.request(:get, "/v1/charges/#{ch_id}")
    bt_id = ch['balance_transaction']
    bt_id = bt_id['id'] if bt_id.is_a?(Hash)
    return nil if bt_id.blank?

    bt = StripeClient.request(:get, "/v1/balance_transactions/#{bt_id}")
    fee = bt['fee'].to_i
    fee.positive? ? (fee / 100.0).round(2) : nil
  rescue StandardError
    nil
  end
end
