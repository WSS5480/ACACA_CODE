# frozen_string_literal: true

module Api
  # COBROS CON TARJETA — dos cuentas de Stripe:
  #   dólares (EE. UU.) y pesos (México). Ver PayCurrency y StripeClient.
  # El contrato, el saldo y la contabilidad SIEMPRE van en dólares; la moneda
  # solo decide en qué cuenta y con qué importe se cobra la tarjeta.
  class StripeController < ApplicationController
    include TokenAuthenticatable

    skip_before_action :authenticate_entity!, only: [:webhook], raise: false
    before_action :authenticate_entity!, except: [:webhook]

    # POST /api/stripe/payment_intent { contract_id, base_amount, waiver_fee, kind, currency }
    # Crea un PaymentIntent (guarda la tarjeta para pagos futuros). El contrato
    # va en USD; con currency=mxn se cobra el equivalente en pesos en Stripe MX.
    def payment_intent
      contract = find_own_contract or return
      base = params[:base_amount].to_f.round(2)
      fee = params[:waiver_fee].to_f.round(2)
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if base <= 0

      cur = requested_currency or return
      tax = (((base + fee) * Product.tax_rate) / 100.0).round(2)
      usd_total = (base + fee + tax).round(2)
      native_total, rate = PayCurrency.convert(usd_total, cur)
      # La tarjeta se cobra al DUEÑO del contrato (cliente), aunque quien inicie
      # el cobro sea el staff desde Gestión de cuenta.
      owner = contract.user || @current_user
      customer_id = ensure_stripe_customer!(owner, cur)

      # save_card (checkbox del cliente, PREMARCADO): si viene en false, la
      # tarjeta NO se guarda en la cuenta para pagos futuros.
      save_card = params[:save_card].nil? ? true : ActiveModel::Type::Boolean.new.cast(params[:save_card])
      pi_params = {
        amount: PayCurrency.smallest_unit(native_total, cur),
        currency: cur,
        customer: customer_id,
        automatic_payment_methods: { enabled: true },
        description: "Contrato #{contract.contract_number.presence || contract.order_ref}",
        metadata: fx_metadata(cur, rate, usd_total, native_total).merge(
          contract_id: contract.id, user_id: @current_user.id, base_amount: base, waiver_fee: fee,
          tax_amount: tax, kind: params[:kind].to_s, apply_to: params[:apply_to].to_s
        )
      }
      apply_save_card!(pi_params, cur, save_card)
      pi = StripeClient.request(:post, '/v1/payment_intents', pi_params, account: PayCurrency.account_of(cur))
      remember_currency!(cur)
      render json: { client_secret: pi['client_secret'], payment_intent_id: pi['id'] }.merge(charge_summary(cur, rate, usd_total, native_total)), status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/multi_payment_intent { allocations: [{contract_id, amount}], currency }
    # UN SOLO pago que cubre VARIOS contratos del cliente: cada monto se aplica
    # a su contrato al confirmar (finalize/webhook). Montos en USD + IVA.
    def multi_payment_intent
      allocs = Array(params[:allocations]).map do |a|
        { contract_id: a[:contract_id].to_i, amount: a[:amount].to_f.round(2) }
      end.select { |a| a[:contract_id].positive? && a[:amount].positive? }
      return render(json: { error: 'Indica al menos un monto' }, status: :unprocessable_entity) if allocs.empty?

      cur = requested_currency or return

      contracts = Contract.where(id: allocs.map { |a| a[:contract_id] }).index_by(&:id)
      allocs.each do |a|
        c = contracts[a[:contract_id]]
        return render(json: { error: 'Contrato no encontrado' }, status: :not_found) unless c
        if @current_user.role&.name == 'cliente' && c.user_id != @current_user.id
          return render(json: { error: 'No autorizado' }, status: :forbidden)
        end
      end

      # EXENCIÓN DE RESPONSABILIDAD por contrato: el pago combinado cobra el
      # mismo % que los pagos individuales de cada contrato (antes NO la
      # cobraba y esos pagos salían sin exención en el registro).
      allocs.each do |a|
        pct = contracts[a[:contract_id]].orders.first.try(:waiver).to_f
        a[:fee] = pct.positive? ? ((a[:amount] * pct) / 100.0).round(2) : 0.0
      end
      base_sum = allocs.sum { |a| a[:amount] }.round(2)
      fee_sum = allocs.sum { |a| a[:fee] }.round(2)
      tax = (((base_sum + fee_sum) * Product.tax_rate) / 100.0).round(2)
      usd_total = (base_sum + fee_sum + tax).round(2)
      native_total, rate = PayCurrency.convert(usd_total, cur)
      customer_id = ensure_stripe_customer!(@current_user, cur)

      nums = allocs.map { |a| contracts[a[:contract_id]].contract_number.presence || contracts[a[:contract_id]].order_ref }
      pi_params = {
        amount: PayCurrency.smallest_unit(native_total, cur),
        currency: cur,
        customer: customer_id,
        automatic_payment_methods: { enabled: true },
        description: "Pago combinado: #{nums.join(', ')}",
        metadata: fx_metadata(cur, rate, usd_total, native_total).merge(
          user_id: @current_user.id, kind: 'multi', tax_amount: tax, waiver_total: fee_sum,
          allocations: allocs.map { |a| { c: a[:contract_id], a: a[:amount], f: a[:fee] } }.to_json
        )
      }
      apply_save_card!(pi_params, cur, true)
      pi = StripeClient.request(:post, '/v1/payment_intents', pi_params, account: PayCurrency.account_of(cur))
      remember_currency!(cur)
      render json: { client_secret: pi['client_secret'], payment_intent_id: pi['id'],
                     base_total: base_sum, waiver_total: fee_sum, tax: tax,
                     total: usd_total }.merge(charge_summary(cur, rate, usd_total, native_total)), status: :ok
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/setup_intent { currency } -> guardar una TARJETA sin pagar
    # (Perfil): queda lista para pagos automáticos y cobros futuros (off-session).
    # La tarjeta se guarda en la cuenta de Stripe de esa moneda.
    def setup_intent
      cur = requested_currency or return
      customer_id = ensure_stripe_customer!(@current_user, cur)
      # Solo TARJETA al guardar desde el Perfil: es lo que el autopago cobra
      # después sin el cliente presente (Apple/Google Pay cuentan como tarjeta).
      si = StripeClient.request(:post, '/v1/setup_intents', {
        customer: customer_id,
        payment_method_types: ['card'],
        usage: 'off_session',
        metadata: { user_id: @current_user.id, source: 'perfil', currency: cur }
      }, account: PayCurrency.account_of(cur))
      render json: { client_secret: si['client_secret'], currency: cur }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # DELETE /api/stripe/payment_methods/:id?currency=usd -> quitar una tarjeta guardada
    def detach_payment_method
      found = nil
      PayCurrency.available.each do |cur|
        acct = PayCurrency.account_of(cur)
        cid = customer_id_for(@current_user, cur)
        next if cid.blank?

        pm = begin
          StripeClient.request(:get, "/v1/payment_methods/#{params[:id]}", nil, account: acct)
        rescue StripeClient::Error
          nil
        end
        next unless pm.is_a?(Hash) && pm['customer'] == cid

        found = acct
        break
      end
      return render(json: { error: 'Tarjeta no encontrada' }, status: :not_found) if found.blank?

      StripeClient.request(:post, "/v1/payment_methods/#{params[:id]}/detach", {}, account: found)
      render json: { ok: true }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/stripe/payment_methods?currency=usd -> tarjetas guardadas del cliente
    # La MISMA tarjeta guardada varias veces (la casilla del pago inicial la
    # re-guardaba en cada compra) se muestra UNA sola vez: Stripe identifica
    # la tarjeta física por 'fingerprint'; se conserva la copia más reciente
    # y las repetidas se desprenden (detach) al vuelo. Es seguro: nada guarda
    # ids de tarjeta — el autopago y el cobro con un clic toman la lista viva.
    #
    # Con dos cuentas devuelve la lista de CADA moneda: una tarjeta guardada en
    # pesos solo sirve para cobrar en pesos.
    def payment_methods
      asked = PayCurrency.normalize(params[:currency].presence || @current_user.try(:pay_currency))
      by_currency = {}
      PayCurrency.available.each do |cur|
        cid = customer_id_for(@current_user, cur)
        by_currency[cur] = cid.present? ? StripeClient.saved_methods(cid, account: PayCurrency.account_of(cur)) : []
      end
      cards = by_currency[asked] || by_currency['usd'] || []
      Rails.logger.info "[stripe] métodos guardados (#{asked}): #{cards.size}"
      render json: { cards: cards, currency: asked, by_currency: by_currency }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/charge_saved { contract_id, base_amount, waiver_fee, payment_method_id, currency }
    # Cobra la tarjeta guardada (off-session) y registra el pago.
    def charge_saved
      contract = find_own_contract or return
      base = params[:base_amount].to_f.round(2)
      fee = params[:waiver_fee].to_f.round(2)
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if base <= 0

      cur = requested_currency or return
      acct = PayCurrency.account_of(cur)
      owner = contract.user || @current_user
      cid = customer_id_for(owner, cur)
      return render(json: { error: 'No hay tarjeta guardada' }, status: :unprocessable_entity) if cid.blank?

      pm = params[:payment_method_id].presence
      if pm.blank?
        pm = StripeClient.saved_methods(cid, account: acct).first&.dig(:id)
        return render(json: { error: 'No hay tarjeta guardada' }, status: :unprocessable_entity) if pm.blank?
      end

      tax = (((base + fee) * Product.tax_rate) / 100.0).round(2)
      usd_total = (base + fee + tax).round(2)
      native_total, rate = PayCurrency.convert(usd_total, cur)
      pi = StripeClient.request(:post, '/v1/payment_intents', {
        amount: PayCurrency.smallest_unit(native_total, cur),
        currency: cur,
        customer: cid,
        payment_method: pm,
        off_session: 'true',
        confirm: 'true',
        description: "Contrato #{contract.contract_number.presence || contract.order_ref}",
        metadata: fx_metadata(cur, rate, usd_total, native_total).merge(
          contract_id: contract.id, user_id: @current_user.id, base_amount: base, waiver_fee: fee,
          tax_amount: tax, kind: 'saved', apply_to: params[:apply_to].to_s
        )
      }, account: acct)
      if pi['status'] == 'succeeded'
        remember_currency!(cur)
        payment = apply_stripe_payment!(pi)
        render json: { ok: true, payment_id: payment&.id, balance: contract.reload.balance,
                       payment_status: contract.payment_status }.merge(charge_summary(cur, rate, usd_total, native_total)), status: :ok
      else
        render json: { error: "El pago no se completo (#{pi['status']})." }, status: :unprocessable_entity
      end
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/stripe/config -> llaves publicables y monedas disponibles.
    # (la usa Gestión de cuenta para cobrar con tarjeta NUEVA tecleada por el
    # staff, y la tienda para saber si puede ofrecer el pago en pesos).
    # OJO: el método NO puede llamarse `config` — chocaría con el `config` interno
    # de Rails en los controladores y rompe TODOS los cobros (recursión infinita).
    def publishable_config
      fx = PayCurrency.config
      render json: {
        publishable_key: StripeClient.publishable_key('us').to_s, # compatibilidad
        accounts: {
          us: { configured: StripeClient.configured?('us'), publishable_key: StripeClient.publishable_key('us').to_s, currency: 'usd' },
          mx: { configured: StripeClient.configured?('mx'), publishable_key: StripeClient.publishable_key('mx').to_s, currency: 'mxn' }
        },
        currencies: fx[:available],
        default_currency: (@current_user.try(:pay_currency).presence || fx[:default]),
        fx: { rates: fx[:rates], base_rate: fx[:base_rate], markup_pct: fx[:markup_pct] }
      }, status: :ok
    end

    # POST /api/stripe/pay_currency { currency } -> recuerda la moneda preferida
    def pay_currency
      cur = requested_currency or return

      remember_currency!(cur)
      render json: { ok: true, currency: cur }, status: :ok
    end

    # POST /api/stripe/finalize { payment_intent_id, currency }
    # Tras confirmar en el navegador: verifica con Stripe y registra el pago (idempotente).
    def finalize
      pi = nil
      accounts = [PayCurrency.account_of(params[:currency])] | StripeClient::ACCOUNTS
      accounts.each do |acct|
        next unless StripeClient.configured?(acct)

        pi = begin
          StripeClient.request(:get, "/v1/payment_intents/#{params[:payment_intent_id]}", nil, account: acct)
        rescue StripeClient::Error
          nil
        end
        break if pi
      end
      return render(json: { error: 'Pago no encontrado' }, status: :not_found) if pi.blank?
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless pi.dig('metadata', 'user_id').to_s == @current_user.id.to_s

      # OXXO / transferencia SPEI: el cliente ya tiene su ficha pero el dinero
      # llega horas después. No es un error: el webhook registra el pago solo.
      if %w[processing requires_action requires_confirmation].include?(pi['status'])
        return render(json: { ok: false, pending: true, status: pi['status'] }, status: :ok)
      end
      return render(json: { error: 'Pago no completado' }, status: :unprocessable_entity) unless pi['status'] == 'succeeded'

      payment = apply_stripe_payment!(pi)
      contract = payment&.contract || Contract.find_by(id: pi.dig('metadata', 'contract_id'))
      render json: { ok: true, balance: contract&.balance, payment_status: contract&.payment_status }, status: :ok
    rescue StripeClient::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/stripe/webhook  (respaldo: registra pagos aunque el navegador se cierre)
    # UNA sola URL para las DOS cuentas: se acepta la petición si la firma cuadra
    # con el secreto de EE. UU. o con el de México.
    def webhook
      payload = request.body.read
      if StripeClient.any_webhook_secret?
        acct = StripeClient.webhook_account(payload, request.headers['Stripe-Signature'])
        return render(json: { error: 'firma invalida' }, status: :bad_request) if acct.blank?
      end

      event = JSON.parse(payload) rescue {}
      if event['type'] == 'payment_intent.succeeded'
        apply_stripe_payment!(event.dig('data', 'object') || {})
      end
      render json: { received: true }, status: :ok
    end

    private

    # Moneda pedida, validada contra lo que HOY se puede cobrar. Si piden pesos
    # sin las llaves de México o sin tipo de cambio, se responde con el error y
    # no se cobra nada (nunca se cambia la moneda a espaldas del cliente).
    def requested_currency
      cur = PayCurrency.normalize(params[:currency].presence || @current_user.try(:pay_currency))
      return cur if PayCurrency.enabled?(cur)

      if cur == 'usd'
        render json: { error: 'Stripe no está configurado' }, status: :unprocessable_entity
      else
        render json: { error: 'El pago en pesos no está disponible en este momento.' }, status: :unprocessable_entity
      end
      nil
    end

    # Guardar la tarjeta para cobros futuros. En pesos se pide SOLO para la
    # tarjeta (payment_method_options) para no esconder los demás métodos que
    # ofrezca Stripe México (OXXO, transferencia), que no se pueden reutilizar.
    def apply_save_card!(pi_params, cur, save_card)
      return unless save_card

      if cur == 'usd'
        pi_params[:setup_future_usage] = 'off_session'
      else
        pi_params[:payment_method_options] = { card: { setup_future_usage: 'off_session' } }
      end
    end

    def fx_metadata(cur, rate, usd_total, native_total)
      { currency: cur, account: PayCurrency.account_of(cur), fx_rate: rate,
        usd_total: usd_total, native_total: native_total }
    end

    def charge_summary(cur, rate, usd_total, native_total)
      { currency: cur, fx_rate: rate, amount_usd: usd_total, amount_native: native_total,
        currency_label: PayCurrency.label(cur) }
    end

    def customer_id_for(user, cur)
      PayCurrency.normalize(cur) == 'mxn' ? user.try(:stripe_customer_id_mx) : user&.stripe_customer_id
    end

    # La moneda que el cliente acaba de usar queda como su preferida (la usa el
    # autopago y se preselecciona la próxima vez).
    def remember_currency!(cur)
      return unless @current_user.respond_to?(:pay_currency)
      return if @current_user.pay_currency.to_s == cur

      @current_user.update_column(:pay_currency, cur)
    rescue StandardError => e
      Rails.logger.warn "[stripe] no se pudo recordar la moneda: #{e.message}"
    end

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

    def ensure_stripe_customer!(user, cur = 'usd')
      cur = PayCurrency.normalize(cur)
      column = cur == 'mxn' ? :stripe_customer_id_mx : :stripe_customer_id
      existing = user.try(column)
      return existing if existing.present?

      customer = StripeClient.request(:post, '/v1/customers', {
        email: user.email, name: [user.name, user.last_name].compact.join(' '),
        metadata: { user_id: user.id, client_number: user.number }
      }, account: PayCurrency.account_of(cur))
      user.update_column(column, customer['id'])
      customer['id']
    end

    # COMISIÓN de Stripe del cargo (para conciliar contra el depósito bancario):
    # se consulta la balance transaction del cargo. Nunca bloquea el pago.
    # Viene en la moneda del cargo; el que llama la pasa a dólares si hace falta.
    def stripe_fee_for(pi, acct = 'us')
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
    rescue StandardError => e
      Rails.logger.warn "stripe_fee_for #{pi['id']}: #{e.message}"
      nil
    end

    # Registra el pago del PI (idempotente por stripe_payment_intent_id).
    # Solo la parte BASE se aplica a la amortizacion; la exención de responsabilidad va en la nota.
    #
    # MONEDA: el importe del pago SIEMPRE se guarda en dólares (los metadatos
    # del intent traen el desglose en USD). Si el cargo fue en pesos, se deja
    # constancia del importe cobrado, el tipo de cambio y la cuenta de Stripe.
    def apply_stripe_payment!(pi)
      pi_id = pi['id']
      return nil if pi_id.blank?
      existing = Payment.find_by(stripe_payment_intent_id: pi_id)
      return existing if existing

      cur = PayCurrency.normalize(pi['currency'].presence || pi.dig('metadata', 'currency'))
      acct = PayCurrency.account_of(cur)
      rate = pi.dig('metadata', 'fx_rate').to_f
      rate = 1.0 unless rate.positive?
      native_total = (pi['amount'].to_i / 100.0).round(2)
      # Comisión de Stripe: viene en la moneda del cargo -> se pasa a dólares.
      fee_native = stripe_fee_for(pi, acct)
      fee_usd = fee_native && rate.positive? ? (fee_native / rate).round(2) : fee_native

      # Pago COMBINADO (varios contratos en un solo cargo): cada asignación se
      # aplica a su contrato; el dedupe por payment_intent cubre el conjunto.
      if pi.dig('metadata', 'kind').to_s == 'multi'
        # Dedupe del CONJUNTO: los pagos combinados llevan sufijo -c<contrato>
        # (la tabla exige un id de Stripe ÚNICO por renglón).
        existing_multi = Payment.where('stripe_payment_intent_id LIKE ?', "#{pi_id}%").order(:id).first
        return existing_multi if existing_multi

        allocs = begin
          JSON.parse(pi.dig('metadata', 'allocations').to_s)
        rescue StandardError
          []
        end
        first_payment = nil
        total = usd_total_of(pi, native_total, rate)
        # base + exención de cada renglón (los intents viejos no traen 'f': fee 0).
        basefee_sum = allocs.sum { |al| al['a'].to_f + al['f'].to_f }.round(2)
        tax_total = pi.dig('metadata', 'tax_amount').to_f
        tax_total = (total - basefee_sum).round(2) if tax_total <= 0 && total > basefee_sum
        allocs.each do |al|
          c = Contract.find_by(id: al['c'])
          next unless c

          amt = al['a'].to_f.round(2)
          next unless amt.positive?

          wfee = al['f'].to_f.round(2)
          share = basefee_sum.positive? ? ((amt + wfee) / basefee_sum) : 0
          note = "Stripe #{pi_id} | pago combinado (total cobrado $#{'%.2f' % total})"
          note += " | exención de responsabilidad $#{'%.2f' % wfee}" if wfee.positive?
          note += " | #{PayCurrency.charge_note((native_total * share).round(2), cur, rate)}" if cur != 'usd'
          pmt = c.payments.new(amount: amt, method: 'stripe', note: note,
                               stripe_payment_intent_id: "#{pi_id}-c#{c.id}")
          # Desglose contable proporcional (IVA y comisión Stripe repartidos por peso del renglón).
          if Payment.column_names.include?('iva_amount')
            pmt.extra_amount = wfee
            pmt.iva_amount = (tax_total * share).round(2)
            pmt.total_charged = (amt + wfee + pmt.iva_amount.to_f).round(2)
            pmt.stripe_fee = (fee_usd * share).round(2) if fee_usd
          end
          assign_charge_currency!(pmt, cur, acct, rate, (native_total * share).round(2))
          pmt.save!
          first_payment ||= pmt
          actor = (defined?(@current_user) && @current_user) || c.user
          num = c.contract_number.presence || c.order_ref
          client_name = [c.user&.name, c.user&.last_name].compact.join(' ').strip
          AuditLog.record!(actor: actor, action: 'payment_online', target: c,
                           label: client_name.present? ? "#{num} · #{client_name}" : num.to_s,
                           details: "Stripe $#{format('%.2f', amt)} (pago combinado, total $#{format('%.2f', total)})" \
                                    "#{cur == 'usd' ? '' : " · #{PayCurrency.charge_note((native_total * share).round(2), cur, rate)}"} · #{pi_id}")
        end
        return first_payment
      end

      contract = Contract.find_by(id: pi.dig('metadata', 'contract_id'))
      return nil unless contract

      base = pi.dig('metadata', 'base_amount').to_f
      fee = pi.dig('metadata', 'waiver_fee').to_f
      total = usd_total_of(pi, native_total, rate)
      base = total if base <= 0
      tax = pi.dig('metadata', 'tax_amount').to_f
      note = "Stripe #{pi_id}"
      note += " | cargos adicionales (enganche/exención) $#{'%.2f' % fee}" if fee > 0
      note += " | IVA $#{'%.2f' % tax}" if tax > 0
      note += " | total cobrado $#{'%.2f' % total}"
      note += " | #{PayCurrency.charge_note(native_total, cur, rate)}" if cur != 'usd'

      pmt = contract.payments.new(amount: base, method: 'stripe', note: note, stripe_payment_intent_id: pi_id)
      # Desglose contable: IVA, exención y total cobrado quedan en columnas (no solo en la nota).
      if Payment.column_names.include?('iva_amount')
        pmt.iva_amount = tax.round(2)
        pmt.extra_amount = fee.round(2)
        pmt.total_charged = total
        pmt.stripe_fee = fee_usd
      end
      assign_charge_currency!(pmt, cur, acct, rate, native_total)
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
                                "#{cur == 'usd' ? '' : " · #{PayCurrency.charge_note(native_total, cur, rate)}"}" \
                                "#{pmt.apply_mode.present? ? " · aplicado a: #{pmt.apply_mode}" : ''} · #{pi_id}")
      pmt
    end

    # Total del cargo EN DÓLARES: de los metadatos cuando existen (siempre en
    # USD) y, para los intents viejos en dólares, del importe del propio cargo.
    def usd_total_of(pi, native_total, rate)
      meta = pi.dig('metadata', 'usd_total').to_f
      return meta.round(2) if meta.positive?

      cur = PayCurrency.normalize(pi['currency'].presence || pi.dig('metadata', 'currency'))
      return native_total if cur == 'usd' || !rate.positive?

      (native_total / rate).round(2)
    end

    def assign_charge_currency!(pmt, cur, acct, rate, native_amount)
      pmt.charge_currency = PayCurrency.label(cur) if pmt.respond_to?(:charge_currency=)
      pmt.charge_amount = native_amount if pmt.respond_to?(:charge_amount=)
      pmt.stripe_account = acct if pmt.respond_to?(:stripe_account=)
      pmt.fx_rate = rate if cur != 'usd' && pmt.respond_to?(:fx_rate=)
    end
  end
end
