# frozen_string_literal: true

# Cobro automatico de cuotas vencidas/del dia con la tarjeta guardada en Stripe.
# Ejecutar diario (Render Cron Job):  bundle exec rails runner "AutopayService.run"
#
# MONEDA: el contrato siempre está en dólares. Se cobra con la tarjeta guardada
# del cliente en la moneda que él eligió la última vez (pay_currency); si en esa
# moneda no tiene tarjeta guardada, se usa la de la otra moneda antes de darse
# por vencido — nunca se deja de cobrar por eso. En pesos, el importe es el
# equivalente del total en USD al tipo de cambio del día más el margen.
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

  # Tarjeta guardada con la que se va a cobrar: primero en la moneda preferida
  # del cliente, y si ahí no tiene ninguna, en la otra moneda disponible.
  # Devuelve { currency:, payment_method:, customer: } o nil.
  def self.pick_method(user)
    return nil if user.blank?

    preferred = PayCurrency.normalize(user.try(:pay_currency))
    ([preferred] + PayCurrency.available).uniq.each do |cur|
      next unless PayCurrency.enabled?(cur)

      cid = cur == 'mxn' ? user.try(:stripe_customer_id_mx) : user.stripe_customer_id
      next if cid.blank?

      pm = StripeClient.saved_methods(cid, account: PayCurrency.account_of(cur)).first&.dig(:id)
      next if pm.blank?

      return { currency: cur, payment_method: pm, customer: cid }
    end
    nil
  end

  # Cobra lo vencido + lo que vence HOY de un contrato. :charged / :skipped / :failed
  def self.charge_contract(contract)
    user = contract.user
    return :skipped if user.blank?

    due = contract.contract_installments.where.not(status: 'paid')
                  .where('due_date <= ?', Date.current)
                  .sum { |i| (i.amount.to_f - i.paid_amount.to_f) }.round(2)
    return :skipped if due <= 0.009

    waiver_pct = contract.orders.first&.waiver.to_f
    fee = waiver_pct > 0 ? (due * waiver_pct / 100.0).round(2) : 0.0

    # Tarjeta o Link guardados: el más reciente (mismo criterio que el Perfil).
    chosen = pick_method(user)
    return :skipped if chosen.blank?

    cur = chosen[:currency]
    acct = PayCurrency.account_of(cur)
    usd_total = (due + fee).round(2)
    native_total, rate = PayCurrency.convert(usd_total, cur)

    pi = StripeClient.request(:post, '/v1/payment_intents', {
      amount: PayCurrency.smallest_unit(native_total, cur),
      currency: cur,
      customer: chosen[:customer],
      payment_method: chosen[:payment_method],
      off_session: 'true',
      confirm: 'true',
      description: "Autopay contrato #{contract.contract_number}",
      metadata: { contract_id: contract.id, user_id: user.id, base_amount: due, waiver_fee: fee, kind: 'autopay',
                  currency: cur, account: acct, fx_rate: rate, usd_total: usd_total, native_total: native_total }
    }, account: acct)

    if pi['status'] == 'succeeded'
      unless Payment.exists?(stripe_payment_intent_id: pi['id'])
        note = "Autopay Stripe #{pi['id']}"
        note += " | exención de responsabilidad $#{'%.2f' % fee}" if fee > 0
        note += " | #{PayCurrency.charge_note(native_total, cur, rate)}" if cur != 'usd'
        attrs = { amount: due, method: 'autopay', note: note, stripe_payment_intent_id: pi['id'] }
        # Desglose contable (autopay no cobra IVA hoy: base + exención).
        if Payment.column_names.include?('extra_amount')
          fee_native = stripe_fee_for(pi, acct)
          attrs[:extra_amount] = fee
          attrs[:total_charged] = usd_total
          attrs[:stripe_fee] = fee_native && rate.positive? ? (fee_native / rate).round(2) : fee_native
        end
        if Payment.column_names.include?('charge_currency')
          attrs[:charge_currency] = PayCurrency.label(cur)
          attrs[:charge_amount] = native_total
          attrs[:stripe_account] = acct
          attrs[:fx_rate] = rate if cur != 'usd'
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
    if e.authentication_required?
      # El banco del cliente exige que ÉL confirme el cargo (3-D Secure/SCA):
      # frecuente con tarjetas emitidas fuera de EE. UU. No es un rechazo; se le
      # avisa para que entre a Mis pagos y pague con su confirmación.
      contract.update_column(:autopay_last_error, "Tu banco pide confirmar el pago: entra a Mis pagos y págalo desde ahí #{Time.current.strftime('%Y-%m-%d')}")
      notify_action_required(contract, user, (due + fee).round(2))
      Rails.logger.info "[Autopay] contrato #{contract.id}: el banco pide autenticación del cliente"
    else
      contract.update_column(:autopay_last_error, "#{e.message.to_s.truncate(120)} #{Time.current.strftime('%Y-%m-%d')}")
      Rails.logger.error "[Autopay] contrato #{contract.id}: #{e.message}"
    end
    :failed
  rescue StandardError => e
    Rails.logger.error "[Autopay] contrato #{contract.id}: #{e.class} #{e.message}"
    :failed
  end

  # Aviso al cliente (correo + bitácora) de que debe confirmar el pago con su
  # banco. Una vez al día por contrato, aunque el cobro se reintente.
  def self.notify_action_required(contract, user, amount)
    return if user&.email.blank?

    # Ya avisado hoy (la bitácora es la memoria: sobrevive reinicios y varios workers).
    return if already_notified_today?(contract)

    UserMailer.with(user: user, contract: contract, amount: amount).send_payment_action_required.deliver_now
    if defined?(AuditLog)
      AuditLog.record!(actor: nil, action: 'autopay_auth_required', target: contract,
                       label: contract.contract_number.presence || "Contrato #{contract.id}",
                       details: "Autopago: el banco del cliente pide que confirme el cargo · $#{'%.2f' % amount} USD · se le avisó por correo")
    end
  rescue StandardError => e
    Rails.logger.error "[Autopay] aviso de autenticación contrato #{contract.id}: #{e.class} #{e.message}"
  end

  def self.already_notified_today?(contract)
    return false unless defined?(AuditLog) && AuditLog.table_exists?

    AuditLog.where(action: 'autopay_auth_required', target_type: 'Contract', target_id: contract.id)
            .where('created_at >= ?', Time.current.beginning_of_day).exists?
  rescue StandardError
    false
  end

  # Comisión de Stripe del cargo (misma consulta que en StripeController), en la
  # MONEDA DEL CARGO. Nunca bloquea.
  def self.stripe_fee_for(pi, acct = 'us')
    ch_id = pi['latest_charge']
    ch_id = ch_id['id'] if ch_id.is_a?(Hash)
    return nil if ch_id.blank?

    ch = StripeClient.request(:get, "/v1/charges/#{ch_id}", nil, account: acct)
    bt_id = ch['balance_transaction']
    bt_id = bt_id['id'] if bt_id.is_a?(Hash)
    return nil if bt_id.blank?

    bt = StripeClient.request(:get, "/v1/balance_transactions/#{bt_id}", nil, account: acct)
    fee = bt['fee'].to_i
    fee.positive? ? (fee / 100.0).round(2) : nil
  rescue StandardError
    nil
  end
end
