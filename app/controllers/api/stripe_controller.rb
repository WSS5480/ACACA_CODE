# frozen_string_literal: true

module Api
  class StripeController < ApplicationController
    include TokenAuthenticatable

    skip_before_action :authenticate_entity!, only: [:webhook], raise: false
    before_action :authenticate_entity!, except: [:webhook]

    # POST /api/stripe/payment_intent { contract_id, base_amount, waiver_fee, kind }
    # Crea un PaymentIntent (guarda la tarjeta para pagos futuros). Montos en USD.
    def payment_intent
      contract = find_own_contract or return
      base = params[:base_amount].to_f.round(2)
      fee = params[:waiver_fee].to_f.round(2)
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if base <= 0

      tax = (((base + fee) * Product.tax_rate) / 100.0).round(2)
      total_cents = ((base + fee + tax) * 100).round
      # La tarjeta se cobra al DUEÑO del contrato (cliente), aunque quien inicie
      # el cobro sea el staff desde Gestión de cuenta.
      customer_id = ensure_stripe_customer!(contract.user || @current_user)

      pi = StripeClient.request(:post, '/v1/payment_intents', {
        amount: total_cents,
        currency: 'usd',
        customer: customer_id,
        setup_future_usage: 'off_session',
        automatic_payment_methods: { enabled: true },
        description: "Contrato #{contract.contract_number.presence || contract.order_ref}",
        metadata: { contract_id: contract.id, user_id: @current_user.id, base_amount: base, waiver_fee: fee, tax_amount: tax, kind: params[:kind].to_s, apply_to: params[:apply_to].to_s }
      })
      render json: { client_secret: pi['client_secret'], payment_intent_id: pi['id'] }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/stripe/payment_methods  -> tarjetas guardadas del cliente
    def payment_methods
      cid = @current_user.stripe_customer_id
      return render(json: { cards: [] }, status: :ok) if cid.blank?

      res = StripeClient.request(:get, '/v1/payment_methods', { customer: cid, type: 'card' })
      cards = (res['data'] || []).map do |pm|
        { id: pm['id'], brand: pm.dig('card', 'brand'), last4: pm.dig('card', 'last4'),
          exp_month: pm.dig('card', 'exp_month'), exp_year: pm.dig('card', 'exp_year') }
      end
      render json: { cards: cards }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/charge_saved { contract_id, base_amount, waiver_fee, payment_method_id }
    # Cobra la tarjeta guardada (off-session) y registra el pago.
    def charge_saved
      contract = find_own_contract or return
      base = params[:base_amount].to_f.round(2)
      fee = params[:waiver_fee].to_f.round(2)
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if base <= 0

      cid = (contract.user || @current_user).stripe_customer_id
      return render(json: { error: 'No hay tarjeta guardada' }, status: :unprocessable_entity) if cid.blank?

      pm = params[:payment_method_id].presence
      if pm.blank?
        res = StripeClient.request(:get, '/v1/payment_methods', { customer: cid, type: 'card' })
        pm = res.dig('data', 0, 'id')
        return render(json: { error: 'No hay tarjeta guardada' }, status: :unprocessable_entity) if pm.blank?
      end

      tax = (((base + fee) * Product.tax_rate) / 100.0).round(2)
      pi = StripeClient.request(:post, '/v1/payment_intents', {
        amount: ((base + fee + tax) * 100).round,
        currency: 'usd',
        customer: cid,
        payment_method: pm,
        off_session: 'true',
        confirm: 'true',
        description: "Contrato #{contract.contract_number.presence || contract.order_ref}",
        metadata: { contract_id: contract.id, user_id: @current_user.id, base_amount: base, waiver_fee: fee, tax_amount: tax, kind: 'saved', apply_to: params[:apply_to].to_s }
      })
      if pi['status'] == 'succeeded'
        payment = apply_stripe_payment!(pi)
        render json: { ok: true, payment_id: payment&.id, balance: contract.reload.balance, payment_status: contract.payment_status }, status: :ok
      else
        render json: { error: "El pago no se completo (#{pi['status']})." }, status: :unprocessable_entity
      end
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/stripe/config -> llave publicable para montar el formulario de tarjeta
    # (la usa Gestión de cuenta para cobrar con tarjeta NUEVA tecleada por el staff).
    # OJO: el método NO puede llamarse `config` — chocaría con el `config` interno
    # de Rails en los controladores y rompe TODOS los cobros (recursión infinita).
    def publishable_config
      render json: { publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'].to_s.presence ||
                                      ENV['NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY'].to_s }, status: :ok
    end

    # POST /api/stripe/finalize { payment_intent_id }
    # Tras confirmar en el navegador: verifica con Stripe y registra el pago (idempotente).
    def finalize
      pi = StripeClient.request(:get, "/v1/payment_intents/#{params[:payment_intent_id]}")
      return render(json: { error: 'Pago no completado' }, status: :unprocessable_entity) unless pi['status'] == 'succeeded'
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless pi.dig('metadata', 'user_id').to_s == @current_user.id.to_s

      payment = apply_stripe_payment!(pi)
      contract = payment&.contract || Contract.find_by(id: pi.dig('metadata', 'contract_id'))
      render json: { ok: true, balance: contract&.balance, payment_status: contract&.payment_status }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/webhook  (respaldo: registra pagos aunque el navegador se cierre)
    def webhook
      payload = request.body.read
      secret = ENV['STRIPE_WEBHOOK_SECRET']
      if secret.present? && !StripeClient.verify_webhook(payload, request.headers['Stripe-Signature'], secret)
        return render(json: { error: 'firma invalida' }, status: :bad_request)
      end

      event = JSON.parse(payload) rescue {}
      if event['type'] == 'payment_intent.succeeded'
        apply_stripe_payment!(event.dig('data', 'object') || {})
      end
      render json: { received: true }, status: :ok
    end

    private

    def find_own_contract
      contract = Contract.find_by(id: params[:contract_id])
      unless contract
        render json: { error: 'Contrato no encontrado' }, status: :not_found
        return nil
      end
      role = @current_user&.role&.name
      unless %w[master admin sistema].include?(role) || contract.user_id == @current_user.id
        render json: { error: 'No autorizado' }, status: :forbidden
        return nil
      end
      contract
    end

    def ensure_stripe_customer!(user)
      return user.stripe_customer_id if user.stripe_customer_id.present?

      customer = StripeClient.request(:post, '/v1/customers', {
        email: user.email, name: [user.name, user.last_name].compact.join(' '),
        metadata: { user_id: user.id, client_number: user.number }
      })
      user.update_column(:stripe_customer_id, customer['id'])
      customer['id']
    end

    # Registra el pago del PI (idempotente por stripe_payment_intent_id).
    # Solo la parte BASE se aplica a la amortizacion; el seguro va en la nota.
    def apply_stripe_payment!(pi)
      pi_id = pi['id']
      return nil if pi_id.blank?
      existing = Payment.find_by(stripe_payment_intent_id: pi_id)
      return existing if existing

      contract = Contract.find_by(id: pi.dig('metadata', 'contract_id'))
      return nil unless contract

      base = pi.dig('metadata', 'base_amount').to_f
      fee = pi.dig('metadata', 'waiver_fee').to_f
      total = (pi['amount'].to_i / 100.0).round(2)
      base = total if base <= 0
      tax = pi.dig('metadata', 'tax_amount').to_f
      note = "Stripe #{pi_id}"
      note += " | cargos adicionales (enganche/seguro) $#{'%.2f' % fee}" if fee > 0
      note += " | IVA $#{'%.2f' % tax}" if tax > 0
      note += " | total cobrado $#{'%.2f' % total}"

      pmt = contract.payments.new(amount: base, method: 'stripe', note: note, stripe_payment_intent_id: pi_id)
      # 'saldo' = el excedente paga principal (acorta plazo y ahorra el cargo financiero).
      pmt.apply_mode = pi.dig('metadata', 'apply_to').to_s
      pmt.save!
      # Bitácora: pagos en línea. En el webhook no hay sesión: el actor es el dueño del contrato.
      actor = (defined?(@current_user) && @current_user) || contract.user
      num = contract.contract_number.presence || contract.order_ref
      client_name = [contract.user&.name, contract.user&.last_name].compact.join(' ').strip
      AuditLog.record!(actor: actor, action: 'payment_online', target: contract,
                       label: client_name.present? ? "#{num} · #{client_name}" : num.to_s,
                       details: "Stripe $#{format('%.2f', base)} (total cobrado $#{format('%.2f', total)})" \
                                "#{pmt.apply_mode.present? ? " · aplicado a: #{pmt.apply_mode}" : ''} · #{pi_id}")
      pmt
    end
  end
end
