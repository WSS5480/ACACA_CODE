# frozen_string_literal: true

module Api
  class ContractsController < ApplicationController
    include TokenAuthenticatable

    # destroy hace sus propias validaciones: staff borra cualquiera; un cliente sólo puede
    # CANCELAR su propio pedido mientras NO haya realizado el pago inicial.

    # GET /api/contracts?user_id=
    def index
      scope = Contract.includes(:user).order(created_at: :desc)
      if client?
        # Un cliente solo ve SUS contratos.
        scope = scope.where(user_id: @current_user.id)
      elsif params[:user_id].present?
        scope = scope.where(user_id: params[:user_id])
      end
      render json: ContractSerializer.new(scope).serializable_hash, status: :ok
    end

    # GET /api/contracts/:id  -> contrato + articulos + tabla de amortizacion
    def show
      contract = Contract.includes(:user, :orders, :contract_installments).find(params[:id])
      return render(json: { error: 'No autorizado' }, status: :forbidden) if client? && contract.user_id != @current_user.id
      data = ContractSerializer.new(contract).serializable_hash[:data][:attributes]
      data[:items] = contract.orders.map { |o| OrderSerializer.new(o).serializable_hash[:data][:attributes] }
      # El CLIENTE no ve el calendario de pagos hasta que realice el pago inicial;
      # el staff siempre lo ve completo.
      pending_initial = !contract.initial_paid?
      data[:pending_initial_payment] = pending_initial
      # Datos completos = comprador capturado Y las 4 referencias (2 MX + 2 US).
      # Con menos referencias ("las guardo después"), el expediente sigue INCOMPLETO.
      first_order = contract.orders.first
      datos_complete = contract.respond_to?(:datos_complete?) ? contract.datos_complete? : true
      # CLIENTE APROBADO que regresa: si esta compra aún no tiene datos, se
      # REUTILIZAN los de su última compra APROBADA (verificada). Menos de 6
      # meses desde la aprobación: se copian solos, sin pedirlos otra vez.
      # Más de 6 meses: se le muestran para CONFIRMAR (correcto / editar).
      if client? && contract.user_id == @current_user.id && first_order.present? && !datos_complete
        src = reusable_datos_source(contract)
        if src && src[:fresh]
          copy_datos!(src[:data_order], first_order)
          first_order = contract.orders.reload.first
          datos_complete = contract.respond_to?(:datos_complete?) ? contract.reload.datos_complete? : true
          if datos_complete
            data[:datos_reused] = true
            begin
              ReferencePing.enqueue_for!(contract)
            rescue StandardError => e
              Rails.logger.warn "[contracts] pings: #{e.message}"
            end
          end
        elsif src
          data[:needs_reconfirm] = true
          data[:previous_datos] = {
            verified_at: src[:verified_at],
            buyer: (src[:buyer] ? BuyerSerializer.new(src[:buyer]).serializable_hash[:data][:attributes] : nil),
            referrals: src[:referrals].map { |r| ReferralSerializer.new(r).serializable_hash[:data][:attributes] }
          }
        end
      end
      data[:datos_complete] = datos_complete
      # El CLIENTE ve su calendario de pagos hasta que: pagó el inicial Y completó sus datos.
      data[:installments] = if client? && (pending_initial || !datos_complete)
                              []
                            else
                              contract.contract_installments.map { |i| ContractInstallmentSerializer.new(i).serializable_hash[:data][:attributes] }
                            end
      # HISTORIAL DE PAGOS con folio para REIMPRIMIR RECIBO (incluye el pago
      # inicial). balance_after = saldo del financiado después de cada abono.
      running = 0.0
      fin_total = contract.financed_amount.to_f
      data[:payments] = contract.payments.order(:paid_at, :id).map do |p|
        running = (running + p.amount.to_f).round(2)
        { id: p.id, paid_at: p.paid_at,
          amount: p.amount.to_f.round(2),
          kind: (p.try(:kind).presence || 'renta'),
          iva_amount: p.try(:iva_amount).to_f.round(2),
          extra_amount: p.try(:extra_amount).to_f.round(2),
          total_charged: (p.try(:total_charged).to_f.positive? ? p.total_charged.to_f : p.amount.to_f).round(2),
          method: p.method,
          reference: (p.respond_to?(:stripe_payment_intent_id) ? p.stripe_payment_intent_id : nil),
          balance_after: [(fin_total - running).round(2), 0].max }
      end
      data[:document] = document_payload(contract)
      # Expediente de la compra: TODO lo que el cliente capturó (comprador, referencias,
      # beneficiario, aval y sus documentos). Visible para el dueño y para el staff.
      buyer_rec = first_order && first_order.respond_to?(:buyer) ? first_order.buyer : nil
      buyer_rec ||= contract.orders.filter_map { |o| o.respond_to?(:buyer) ? o.buyer : nil }.first
      gua_rec = contract.orders.filter_map { |o| o.respond_to?(:guarantor) ? o.guarantor : nil }.first
      ben_rec = contract.orders.filter_map(&:beneficiary).first || contract.user&.beneficiaries&.first
      refs_rec = contract.orders.map(&:referrals).find(&:present?) || []
      data[:expediente] = {
        buyer: buyer_rec ? BuyerSerializer.new(buyer_rec).serializable_hash[:data][:attributes] : nil,
        guarantor: gua_rec ? GuarantorSerializer.new(gua_rec).serializable_hash[:data][:attributes] : nil,
        beneficiary: ben_rec ? BeneficiarySerializer.new(ben_rec).serializable_hash[:data][:attributes] : nil,
        referrals: refs_rec.map { |rf| ReferralSerializer.new(rf).serializable_hash[:data][:attributes] }
      }
      render json: { data: data }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts  { user_id, product_ids:[], downpayment, weeks }
    # Crea un contrato con UNO O VARIOS articulos y UN pago semanal combinado.
    def create
      role_name = @current_user&.role&.name
      is_client = role_name == 'cliente'
      is_staff  = %w[master admin].include?(role_name)
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless is_client || is_staff

      # Un cliente solo crea contratos para si mismo; el staff puede indicar user_id.
      user = is_client ? @current_user : User.find_by(id: params[:user_id])
      return render(json: { error: 'Usuario no encontrado' }, status: :not_found) unless user

      product_ids = Array(params[:product_ids]).map(&:to_i).reject(&:zero?)
      products = Product.where(id: product_ids).to_a
      return render(json: { error: 'Selecciona al menos un producto' }, status: :unprocessable_entity) if products.empty?

      total = products.sum { |p| p.total_price.to_f }.round(2)  # precio de contado
      cash_sale = ActiveModel::Type::Boolean.new.cast(params[:cash])

      beneficiary_id_cash = params[:beneficiary_id].present? ? user.beneficiaries.where(id: params[:beneficiary_id]).pick(:id) : nil
      if cash_sale
        # VENTA DE CONTADO: contrato pagado, sin credito ni amortizacion.
        contract = nil
        ActiveRecord::Base.transaction do
          contract = Contract.create!(
            user: user, status: 'paid',
            total_amount: total, downpayment: total, financed_amount: 0,
            weekly_payment: 0, weeks: 0, frequency: 'weekly', start_date: Date.current
          )
          products.each do |prod|
            contract.orders.create!(
              user_id: user.id, product_id: prod.id,
              user_name: user.name, user_last_name: user.last_name, user_email: user.email,
              product_title: prod.title, product_asin: prod.asin,
              product_price: prod.price, product_price_with_discount: prod.price_with_discount,
              product_original_price: prod.original_price,
              product_turns: prod.turns, product_decimal_factor: prod.decimal_factor,
              used_credit: 0, downpayment: total, weekly_payment: 0, credit_duration: 0,
              beneficiary_id: beneficiary_id_cash,
              status: 'approved'
            )
          end
        end
        return render(json: { data: ContractSerializer.new(contract).serializable_hash[:data][:attributes] }, status: :created)
      end

      weeks = params[:weeks].to_i
      return render(json: { error: 'Plazo (semanas) invalido' }, status: :unprocessable_entity) if weeks <= 0

      down = params[:downpayment].to_f
      min_down = (total * 0.10).round(2)
      return render(json: { error: "El enganche minimo es $#{min_down} (10% del precio de contado)" }, status: :unprocessable_entity) if down + 0.01 < min_down
      return render(json: { error: 'El enganche no puede ser mayor al precio de contado' }, status: :unprocessable_entity) if down > total

      # PRINCIPAL = contado - enganche.
      # FINANCIADO (a pagar) = principal x 1.25 (cargo financiero).
      # El credito cubre el FINANCIADO completo (con cargo incluido): todo lo
      # que rebase el credito debe irse al enganche.
      principal = (total - down).round(2)
      financed = (principal * Product.finance_factor).round(2)

      available = user.credit&.amount.to_f
      return render(json: { error: "El monto a financiar ($#{financed}) supera el credito disponible ($#{available.round(2)}); sube el enganche" }, status: :unprocessable_entity) if financed > available + 0.01

      freq = %w[weekly biweekly monthly].include?(params[:frequency].to_s) ? params[:frequency].to_s : 'weekly'
      waiver_pct = ActiveModel::Type::Boolean.new.cast(params[:waiver]) ? Product.waiver_rate : nil
      # Beneficiario (opcional pero recomendado): debe pertenecer al cliente.
      beneficiary_id = params[:beneficiary_id].present? ? user.beneficiaries.where(id: params[:beneficiary_id]).pick(:id) : nil
      weekly = (financed / weeks).round(2)
      min_wk = Product.min_weekly_for(weeks)
      if financed > 0 && weekly < min_wk
        if min_wk <= 10
          # Plazo corto: se mantiene el pago de $10/sem y se reducen las semanas;
          # la ultima semana liquida el resto del saldo.
          weeks = [(financed / 10.0).ceil, 1].max
          weekly = [10.0, financed].min.round(2)
        else
          return render(json: { error: "El pago semanal combinado ($#{weekly}) debe ser al menos $#{min_wk} para este plazo. Agrega mas articulos, sube el enganche o baja el plazo." }, status: :unprocessable_entity)
        end
      end

      contract = nil
      ActiveRecord::Base.transaction do
        contract = Contract.create!(
          user: user, status: 'active',
          total_amount: total, downpayment: down, financed_amount: financed,
          weekly_payment: weekly, weeks: weeks, frequency: freq,
          # Pago automático de la CUENTA: los contratos nuevos nacen con el
          # mismo ajuste que el cliente eligió en su Perfil.
          autopay: (User.column_names.include?('autopay') && user.autopay ? true : false),
          start_date: (params[:start_date].present? ? ((Date.parse(params[:start_date].to_s) rescue Date.current)) : Date.current)
        )
        products.each do |prod|
          contract.orders.create!(
            user_id: user.id, product_id: prod.id,
            user_name: user.name, user_last_name: user.last_name, user_email: user.email,
            product_title: prod.title, product_asin: prod.asin,
            product_price: prod.price, product_price_with_discount: prod.price_with_discount,
            product_original_price: prod.original_price,
            product_turns: prod.turns, product_decimal_factor: prod.decimal_factor,
            used_credit: 0, downpayment: 0, weekly_payment: 0, credit_duration: weeks,
            beneficiary_id: beneficiary_id, waiver: waiver_pct,
            status: 'approved'
          )
        end
        if user.credit.present? && financed > 0
          user.credit.update!(amount: (user.credit.amount - financed).round(2))
        end
        contract.build_amortization!
      end

      render json: { data: ContractSerializer.new(contract).serializable_hash[:data][:attributes] }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/contracts/:id/record_payment  { amount, method, note }
    def record_payment
      contract = Contract.find(params[:id])
      unless staff? || (client? && contract.user_id == @current_user.id)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end
      amount = params[:amount].to_f
      return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if amount <= 0

      paid_at = params[:paid_on].present? ? ((Time.zone.parse(params[:paid_on].to_s) rescue nil)) : nil
      pmt = contract.payments.new(amount: amount, method: params[:method], note: params[:note], paid_at: paid_at)
      # 'saldo' = el excedente paga principal (acorta plazo y ahorra interés); default = 'plazo'.
      pmt.apply_mode = params[:apply_to].to_s if params[:apply_to].present?
      pmt.save!
      contract.reload
      AuditLog.record!(actor: @current_user, action: 'payment_recorded', target: contract,
                       label: audit_contract_label(contract),
                       details: "Pago $#{format('%.2f', amount)} · método: #{params[:method].presence || 'n/d'}" \
                                "#{params[:apply_to].present? ? " · aplicado a: #{params[:apply_to]}" : ''}" \
                                " · saldo restante: $#{format('%.2f', contract.balance)}")
      render json: {
        ok: true,
        balance: contract.balance,
        payment_status: contract.payment_status,
        available_credit: contract.user&.available_credit
      }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    # POST /api/contracts/:id/autopay  { enabled: true|false }
    # Activa/desactiva el cobro automatico (requiere tarjeta guardada en Stripe).
    def autopay
      contract = Contract.find(params[:id])
      unless staff? || (client? && contract.user_id == @current_user.id)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      if enabled
        cid = contract.user&.stripe_customer_id
        has_card = false
        if cid.present? && StripeClient.configured?
          pms = StripeClient.request(:get, '/v1/payment_methods', { customer: cid, type: 'card' }) rescue { 'data' => [] }
          has_card = (pms['data'] || []).any?
        end
        return render(json: { error: 'Necesitas una tarjeta guardada: realiza un pago con tarjeta primero.' }, status: :unprocessable_entity) unless has_card
      end

      contract.update!(autopay: enabled, autopay_last_error: nil)
      render json: { ok: true, autopay: contract.autopay }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts/autopay_all { enabled }  (cliente, desde su Perfil)
    # PAGO AUTOMÁTICO de TODA la cuenta: activa/desactiva el cobro automático de
    # TODOS los contratos activos según los términos de cada uno, y deja el
    # ajuste en la cuenta para que los contratos NUEVOS nazcan igual.
    def autopay_all
      return render(json: { error: 'Solo el cliente puede ajustar su pago automático' }, status: :forbidden) unless client?

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      if enabled
        cid = @current_user.stripe_customer_id
        has_card = false
        if cid.present? && StripeClient.configured?
          pms = begin
            StripeClient.request(:get, '/v1/payment_methods', { customer: cid, type: 'card' })
          rescue StandardError
            { 'data' => [] }
          end
          has_card = (pms['data'] || []).any?
        end
        return render(json: { error: 'Guarda primero una tarjeta (Perfil → Tarjeta para pagos automáticos).' }, status: :unprocessable_entity) unless has_card
      end

      scope = Contract.where(user_id: @current_user.id, status: 'active')
      scope.update_all(autopay: enabled, autopay_last_error: nil)
      @current_user.update_column(:autopay, enabled) if User.column_names.include?('autopay')
      AuditLog.record!(actor: @current_user, action: 'autopay_all_changed', target: @current_user,
                       label: [@current_user.name, @current_user.last_name].compact.join(' '),
                       details: "Pago automático de TODA la cuenta: #{enabled ? 'ACTIVADO' : 'desactivado'} (#{scope.count} contrato(s))")
      render json: { ok: true, autopay: enabled, contracts: scope.count }, status: :ok
    end

    # POST /api/contracts/:id/set_frequency { frequency: weekly|biweekly|monthly }
    # Cambia la FRECUENCIA de pago del contrato (semanal, quincenal o mensual):
    # el pago por periodo se escala y el calendario pendiente se reconstruye
    # manteniendo el saldo. Cliente (su contrato) o staff.
    def set_frequency
      contract = Contract.find(params[:id])
      unless staff? || (client? && contract.user_id == @current_user.id)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end

      f = params[:frequency].to_s
      return render(json: { error: 'Frecuencia inválida' }, status: :unprocessable_entity) unless %w[weekly biweekly monthly].include?(f)
      return render(json: { error: 'Este contrato ya está liquidado' }, status: :unprocessable_entity) if contract.balance <= 0

      old = contract.freq
      return render(json: { ok: true, frequency: f }, status: :ok) if old == f

      contract.update!(frequency: f)
      contract.rebuild_pending_schedule!
      AuditLog.record!(actor: @current_user, action: 'contract_frequency_changed', target: contract,
                       label: audit_contract_label(contract),
                       details: "Frecuencia de pago: #{old} → #{f} · pago por periodo $#{format('%.2f', contract.period_payment)} · #{contract.contract_installments.where.not(status: 'paid').count} cuota(s) pendientes")
      render json: { ok: true, frequency: f, period_payment: contract.period_payment,
                     next_due_date: contract.next_due_date }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # DELETE /api/contracts/:id  -> herramienta de limpieza (pruebas). Restaura el saldo al credito.
    # POST /api/contracts/:id/set_next_due { date: 'YYYY-MM-DD' }  (solo master/admin — PRUEBAS)
    # Mueve el PRÓXIMO vencimiento pendiente a la fecha dada y desplaza el resto de las
    # cuotas pendientes la misma cantidad de días. Fechas pasadas simulan atrasos
    # (vencidos + moratorios) para probar el sistema de cobranza.
    def set_next_due
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff?

      contract = Contract.find(params[:id])
      new_date = Date.parse(params[:date].to_s) rescue nil
      return render(json: { error: 'Fecha inválida (YYYY-MM-DD)' }, status: :unprocessable_entity) unless new_date

      first_pending = contract.contract_installments.where.not(status: 'paid').order(:number).first
      return render(json: { error: 'Este contrato no tiene cuotas pendientes' }, status: :unprocessable_entity) unless first_pending

      delta = (new_date - first_pending.due_date).to_i
      contract.contract_installments.where.not(status: 'paid').find_each do |inst|
        inst.update_columns(due_date: inst.due_date + delta)
      end
      contract.reload
      AuditLog.record!(actor: @current_user, action: 'due_date_moved', target: contract,
                       label: audit_contract_label(contract),
                       details: "Próximo vencimiento movido #{delta >= 0 ? '+' : ''}#{delta} días → #{new_date.strftime('%d/%m/%Y')} (herramienta de PRUEBAS)")
      render json: {
        ok: true, moved_days: delta,
        next_due_date: contract.next_due_date,
        days_past_due: contract.days_past_due,
        past_due_amount: contract.past_due_amount,
        late_fee_amount: (contract.respond_to?(:late_fee_amount) ? contract.late_fee_amount : 0),
        payment_status: contract.payment_status
      }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts/:id/set_status { status: 'returned' | 'charged_off' | 'active' }
    # Estado de la CUENTA (solo master/admin): devuelto (mercancía devuelta),
    # castigado (incobrable) o reactivado. Queda en la bitácora de auditoría.
    def set_status
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff?

      contract = Contract.find(params[:id])
      st = params[:status].to_s
      return render(json: { error: 'Estado inválido' }, status: :unprocessable_entity) unless %w[returned charged_off active].include?(st)
      unless contract.initial_paid?
        return render(json: { error: 'Un pedido sin pago inicial se CANCELA (se elimina), no se marca devuelto/castigado.' }, status: :unprocessable_entity)
      end

      old = contract.status
      contract.update!(status: st)
      # CONTABILIDAD: castigar la cuenta registra el saldo como gasto por
      # incobrable; reactivarla revierte ese gasto (renglón negativo).
      if defined?(Expense) && Expense.table_exists?
        begin
          num = contract.contract_number.presence || contract.order_ref
          if st == 'charged_off' && contract.balance.positive?
            Expense.create!(expense_date: Date.current, category: 'incobrable', amount: contract.balance,
                            description: "Castigo de #{num} (saldo al castigar)",
                            contract_id: contract.id, created_by_id: @current_user&.id)
          elsif st == 'active' && old == 'charged_off'
            prev = Expense.where(category: 'incobrable', contract_id: contract.id).sum(:amount).to_f.round(2)
            if prev.positive?
              Expense.create!(expense_date: Date.current, category: 'incobrable', amount: -prev,
                              description: "Reversión de castigo de #{num} (cuenta reactivada)",
                              contract_id: contract.id, created_by_id: @current_user&.id)
            end
          end
        rescue StandardError => e
          Rails.logger.error "castigo contable contrato #{contract.id}: #{e.message}"
        end
      end
      labels = { 'returned' => 'DEVUELTO (mercancía devuelta)', 'charged_off' => 'CASTIGADO (cuenta incobrable)', 'active' => 'ACTIVO (cuenta reactivada)' }
      AuditLog.record!(actor: @current_user, action: 'contract_status_changed', target: contract,
                       label: audit_contract_label(contract), details: "#{old} → #{st} · #{labels[st]}")
      render json: { ok: true, status: contract.status, payment_status: contract.payment_status }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts/:id/generate_document  { send_whatsapp: true }
    # Genera el contrato del cliente desde la plantilla legal (rellena carátula, montos y
    # tabla de pagos) y le avisa por WhatsApp para que entre a firmarlo. Sólo staff.
    def generate_document
      unless %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(@current_user&.role&.name)
        return render json: { error: 'No autorizado' }, status: :forbidden
      end
      contract = Contract.find(params[:id])
      unless contract.respond_to?(:document_text)
        return render json: { error: 'Falta la migración de firma (bin/rails db:migrate).' }, status: :unprocessable_entity
      end
      unless contract.initial_paid?
        return render json: { error: 'El contrato se genera hasta que el cliente realice el pago inicial.' }, status: :unprocessable_entity
      end
      if contract.signed_at.present?
        return render json: { error: 'Este contrato ya fue FIRMADO; no se puede regenerar.' }, status: :unprocessable_entity
      end

      contract.assign_contract_number!
      text = ContractDocument.render(contract)
      return render(json: { error: 'La plantilla del contrato está vacía (Seguridad → Control de documentos legales).' }, status: :unprocessable_entity) if text.strip.blank?

      contract.update!(document_text: text, document_generated_at: Time.current)

      wa = nil
      em = nil
      if ActiveModel::Type::Boolean.new.cast(params[:send_whatsapp])
        wa = send_signing_whatsapp(contract)
        # SIEMPRE por los DOS medios: el enlace de firma va por WhatsApp Y por correo
        # (el cliente firma desde donde le quede más cómodo, con dedo o mouse).
        em = send_signing_email(contract)
        contract.update_column(:document_sent_at, Time.current) if wa[:ok] || (em && em[:ok])
      end
      vias = []
      vias << "WhatsApp a #{wa[:sent_to]}" if wa && wa[:ok]
      vias << "correo a #{em[:sent_to]}" if em && em[:ok]
      sent_via = vias.any? ? vias.join(' y ') : 'sin envío'
      if wa && em && !wa[:ok] && !em[:ok] && defined?(WaAlert)
        WaAlert.notify("Enviar a firma #{contract.contract_number}", "WhatsApp: #{wa[:error]} · Correo: #{em[:error]}")
      end
      AuditLog.record!(actor: @current_user, action: 'contract_generated', target: contract,
                       label: audit_contract_label(contract),
                       details: "Documento generado para firma · aviso: #{sent_via}")
      render json: { ok: true, generated_at: contract.document_generated_at, whatsapp: wa, email: em }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    # POST /api/contracts/:id/confirm_datos
    # Cliente que regresa (>6 meses desde su última aprobación): confirma que
    # sus datos siguen correctos — se COPIAN a esta compra (cada orden guarda
    # su propia copia, con candado). También se usa antes de "Editar".
    def confirm_datos
      contract = Contract.find(params[:id])
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless client? && contract.user_id == @current_user.id

      first_order = contract.orders.first
      return render(json: { error: 'Esta compra no tiene artículos' }, status: :unprocessable_entity) unless first_order

      src = reusable_datos_source(contract)
      return render(json: { error: 'No encontramos datos anteriores verificados; captúralos de nuevo.' }, status: :unprocessable_entity) unless src

      copy_datos!(src[:data_order], first_order)
      fo = first_order.reload
      # Datos completos por reutilización -> también se encolan las verificaciones.
      begin
        ReferencePing.enqueue_for!(contract.reload)
      rescue StandardError => e
        Rails.logger.warn "[contracts] pings: #{e.message}"
      end
      render json: { ok: true,
                     datos_complete: (contract.respond_to?(:datos_complete?) ? contract.reload.datos_complete? : true),
                     first_order_id: fo.id }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/contracts/:id/sign  { signature: 'data:image/png;base64,...', name: 'Eddie Cantu' }
    # El CLIENTE firma su contrato (dibuja con dedo o mouse). La firma se guarda en su expediente.
    def sign
      contract = Contract.find(params[:id])
      return render(json: { error: 'No autorizado' }, status: :forbidden) unless client? && contract.user_id == @current_user.id
      return render(json: { error: 'Tu contrato aún no está listo para firma.' }, status: :unprocessable_entity) if !contract.respond_to?(:document_text) || contract.document_text.blank?
      return render(json: { error: 'Este contrato ya fue firmado.' }, status: :unprocessable_entity) if contract.signed_at.present?

      m = params[:signature].to_s.match(%r{\Adata:image/(png|jpeg);base64,(.+)\z}m)
      return render(json: { error: 'Firma inválida.' }, status: :unprocessable_entity) unless m

      bin = Base64.decode64(m[2])
      return render(json: { error: 'La firma está vacía: dibuja tu firma en el recuadro.' }, status: :unprocessable_entity) if bin.bytesize < 400

      ext = m[1] == 'png' ? 'png' : 'jpg'
      contract.signature.attach(io: StringIO.new(bin), filename: "firma_contrato_#{contract.id}.#{ext}", content_type: "image/#{m[1]}")
      contract.update!(
        signed_at: Time.current,
        signature_name: params[:name].to_s.strip.presence || [@current_user.name, @current_user.last_name].compact.join(' '),
        signature_ip: request.remote_ip
      )
      AuditLog.record!(actor: @current_user, action: 'contract_signed', target: contract,
                       label: audit_contract_label(contract),
                       details: "Firmado por #{contract.signature_name} desde IP #{contract.signature_ip}")
      render json: { ok: true, signed_at: contract.signed_at }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    end

    def destroy
      contract = Contract.find(params[:id])
      unpaid = !contract.initial_paid?

      if client?
        # El cliente puede CANCELAR su propio pedido sólo si aún no paga el pago inicial.
        return render(json: { error: 'No autorizado' }, status: :forbidden) unless contract.user_id == @current_user.id
        unless unpaid
          return render(json: { error: 'Este contrato ya tiene pagos registrados; contáctanos para cualquier aclaración.' }, status: :unprocessable_entity)
        end
      elsif !staff?
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end

      user = contract.user

      # REEMBOLSO (opcional, solo staff, contrato CON pagos): la interfaz
      # pregunta y manda refund=1 (SÍ, a la forma de pago original) o refund=0.
      refund_notes = []
      if staff? && !unpaid && ActiveModel::Type::Boolean.new.cast(params[:refund])
        refund_notes = refund_contract_payments!(contract)
      end

      # Crédito a restaurar: en un pedido SIN pagar se consumió el FINANCIADO
      # completo (con cargo financiero); en un contrato pagado (herramienta de
      # staff) se restaura el saldo pendiente.
      restore = unpaid ? [contract.financed_amount.to_f.round(2), 0].max : contract.balance
      ActiveRecord::Base.transaction do
        if user&.credit && restore > 0
          cr = user.credit
          limit = (cr.respond_to?(:credit_limit) ? cr.credit_limit : nil) || cr.amount
          cr.update!(amount: [cr.amount.to_f + restore, limit.to_f].min.round(2))
        end
        ReferencePing.where(contract_id: contract.id).delete_all if defined?(ReferencePing) && ReferencePing.table_exists?
        PaymentCommitment.where(contract_id: contract.id).delete_all if defined?(PaymentCommitment) && PaymentCommitment.table_exists?
        if unpaid || (staff? && ActiveModel::Type::Boolean.new.cast(params[:purge]))
          # Cancelación de un pedido sin pago — o borrado COMPLETO por un admin
          # (purge): se elimina TODO el pedido, artículos incluidos, para que no
          # queden órdenes huérfanas en el pipeline.
          contract.orders.find_each(&:destroy!)
        else
          contract.orders.update_all(contract_id: nil)
        end
        contract.destroy!
      end
      AuditLog.record!(actor: @current_user, action: 'contract_deleted', target: contract,
                       label: audit_contract_label(contract),
                       details: "#{unpaid ? 'Pedido SIN pagar cancelado (artículos eliminados)' : 'Contrato eliminado'}" \
                                " · cliente: #{[user&.name, user&.last_name].compact.join(' ')}" \
                                " · crédito restaurado: $#{format('%.2f', restore)}" \
                                "#{refund_notes.any? ? " · reembolsos: #{refund_notes.join(' | ')}" : ''}")
      render json: { ok: true, refunds: refund_notes }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Contrato no encontrado' }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    # REEMBOLSO a la FORMA DE PAGO ORIGINAL: todos los pagos del contrato hechos
    # con tarjeta (Stripe) se reembolsan a esa misma tarjeta. Un cargo COMPARTIDO
    # entre varios contratos (pago múltiple) se reembolsa SOLO por la parte de
    # este contrato + su IVA proporcional. Los pagos manuales (efectivo/depósito)
    # se listan para reembolsarlos a mano. Devuelve notas para la Bitácora.
    def refund_contract_payments!(contract)
      notes = []
      contract.payments.order(:id).each do |p|
        pi_raw = p.respond_to?(:stripe_payment_intent_id) ? p.stripe_payment_intent_id.to_s : ''
        if pi_raw.blank?
          notes << "manual $#{format('%.2f', p.amount)} (#{p.method.presence || 'sin método'}): reembolsar a mano"
          next
        end
        multi = pi_raw.match(/\A(pi_[A-Za-z0-9]+)-c\d+\z/)
        pi_id = multi ? multi[1] : pi_raw
        begin
          if multi
            cents = ((p.amount.to_f * (1 + Product.tax_rate / 100.0)) * 100).round
            StripeClient.request(:post, '/v1/refunds', { payment_intent: pi_id, amount: cents })
            note = "Stripe $#{format('%.2f', cents / 100.0)} (parcial de #{pi_id})"
            refunded_total = (cents / 100.0).round(2)
          else
            StripeClient.request(:post, '/v1/refunds', { payment_intent: pi_id })
            note = "Stripe reembolso COMPLETO de #{pi_id} ($#{format('%.2f', p.amount)} + cargos)"
            refunded_total = (p.try(:total_charged).to_f.positive? ? p.total_charged : p.amount).to_f.round(2)
          end
          notes << note
          # Libro contable: el reembolso entra como renglón NEGATIVO y sobrevive
          # aunque el contrato (y sus pagos) se eliminen enseguida.
          if defined?(LedgerEntry)
            LedgerEntry.record_refund!(contract: contract, payment: p, total: refunded_total,
                                       reference: pi_id, by: @current_user, description: note)
          end
          AuditLog.record!(actor: @current_user, action: 'payment_refunded', target: contract,
                           label: audit_contract_label(contract), details: note)
        rescue StandardError => e
          notes << "⚠ #{pi_id}: #{e.message}"
        end
      end
      notes
    end

    # Fuente para REUTILIZAR datos: la última orden APROBADA (verificación
    # completa) del cliente con comprador y referencias capturados.
    # fresh = la aprobación tiene menos de 6 meses (no se vuelve a pedir nada).
    def reusable_datos_source(contract)
      # Fuente para PREPOBLAR: primero la última compra APROBADA (verificada);
      # si no hay, CUALQUIER compra anterior con datos capturados — el cliente
      # nunca vuelve a teclear lo que ya nos dio. "fresh" (auto-copia sin
      # preguntar) sólo aplica a datos VERIFICADOS hace menos de 6 meses; los
      # no verificados siempre se muestran para CONFIRMAR/actualizar.
      approved = Order.where(user_id: contract.user_id, admin_approved: true)
                      .where.not(contract_id: contract.id)
                      .order(approved_at: :desc, id: :desc).limit(25).to_a
      others = Order.where(user_id: contract.user_id)
                    .where.not(contract_id: contract.id)
                    .where(admin_approved: [false, nil])
                    .order(id: :desc).limit(25).to_a
      (approved + others).each do |cand|
        group = cand.contract_id.present? ? Order.where(contract_id: cand.contract_id).order(:id).to_a : [cand]
        data_order = group.find { |o| o.respond_to?(:buyer) && o.buyer.present? } ||
                     group.find { |o| o.referrals.exists? }
        next unless data_order
        next unless data_order.buyer.present? || data_order.referrals.exists?

        was_approved = cand.respond_to?(:admin_approved) && cand.admin_approved
        verified_at = was_approved ? (cand.approved_at || cand.updated_at) : nil
        return {
          data_order: data_order,
          buyer: data_order.buyer,
          referrals: data_order.referrals.to_a,
          verified_at: verified_at,
          fresh: was_approved && verified_at.present? && verified_at >= 6.months.ago
        }
      end
      nil
    end

    # Copia comprador (con sus documentos), referencias y aval de una orden
    # aprobada anterior a la PRIMERA orden de esta compra. Cada orden conserva
    # SU PROPIA copia (candado por orden): editar los datos de una compra nueva
    # nunca toca lo que quedó verificado en las anteriores.
    def copy_datos!(src_order, target_order)
      ActiveRecord::Base.transaction do
        if src_order.respond_to?(:buyer) && src_order.buyer.present? && target_order.buyer.blank?
          nb = Buyer.new(src_order.buyer.attributes.except('id', 'order_id', 'created_at', 'updated_at'))
          nb.order_id = target_order.id
          nb.save!
          %i[identification proof_of_address proof_of_income].each do |att|
            nb.public_send(att).attach(src_order.buyer.public_send(att).blob) if src_order.buyer.public_send(att).attached?
          end
        end
        if target_order.referrals.none?
          src_order.referrals.find_each do |rf|
            Referral.create!(rf.attributes.except('id', 'created_at', 'updated_at').merge('order_id' => target_order.id))
          end
        end
        if src_order.respond_to?(:guarantor) && src_order.guarantor.present? && target_order.guarantor.blank?
          ng = Guarantor.new(src_order.guarantor.attributes.except('id', 'order_id', 'created_at', 'updated_at'))
          ng.order_id = target_order.id
          ng.save!
          %i[identification proof_of_address].each do |att|
            ng.public_send(att).attach(src_order.guarantor.public_send(att).blob) if src_order.guarantor.public_send(att).attached?
          end
        end
      end
    end

    # Etiqueta legible del contrato para la bitácora de auditoría.
    def audit_contract_label(contract)
      num = contract.contract_number.presence || (contract.respond_to?(:order_ref) ? contract.order_ref : "PED-#{contract.id}")
      client = [contract.user&.name, contract.user&.last_name].compact.join(' ').strip
      client.present? ? "#{num} · #{client}" : num.to_s
    end

    # Estado del documento/firma para el show (cliente y staff).
    def document_payload(contract)
      return nil unless contract.respond_to?(:document_text)

      sig_url = nil
      if contract.signature.attached?
        sig_url = begin
          contract.signature.url(expires_in: 1.hour)
        rescue StandardError
          begin
            Rails.application.routes.url_helpers.rails_blob_url(contract.signature)
          rescue StandardError
            nil
          end
        end
      end
      {
        generated_at: contract.document_generated_at,
        sent_at: contract.document_sent_at,
        signed_at: contract.signed_at,
        signature_name: contract.signature_name,
        signature_url: sig_url,
        text: contract.document_text
      }
    end

    def send_signing_email(contract)
      user = contract.user
      return { ok: false, error: 'El cliente no tiene email registrado' } if user&.email.blank?

      UserMailer.with(user: user, contract: contract).send_contract_signing.deliver_now
      { ok: true, sent_to: user.email }
    rescue StandardError => e
      Rails.logger.error "No se pudo enviar el correo de firma (contrato #{contract.id}): #{e.class}: #{e.message}"
      { ok: false, error: "No se pudo enviar el correo: #{e.class}: #{e.message.to_s.strip[0, 200]}" }
    end

    def send_signing_whatsapp(contract)
      user = contract.user
      return { ok: false, error: 'El cliente no tiene teléfono registrado' } if user&.phone.blank?

      front = ENV['FRONT_HOST'].presence || 'https://www.acasamx.com'
      link = "#{front.chomp('/')}/contratos/#{contract.id}/firmar"
      # Texto EDITABLE en Configuración → Respuestas WhatsApp.
      body = WaAutoText.render('firma', nombre: user.name, contrato: contract.contract_number, enlace: link)
      # Fuera de la ventana de 24 h el texto libre NO se entrega: se reenvía como
      # PLANTILLA aprobada (firma_contrato) para que al cliente SÍ le llegue.
      r = WhatsappOutbound.deliver(phone: user.phone, text: body, event: 'firma',
                                   params: [user.name.to_s, contract.contract_number.to_s, link],
                                   user: user, actor: @current_user)
      return { ok: true, sent_to: user.phone, via: r[:via] } if r[:ok]

      { ok: false, error: "No se pudo enviar el WhatsApp: #{r[:error]} (el contrato SÍ se generó)." }
    end

    def authorize_staff!
      render json: { error: 'No autorizado' }, status: :forbidden unless staff?
    end

    def staff?
      %w[master admin].include?(@current_user&.role&.name)
    end

    def client?
      @current_user&.role&.name == 'cliente'
    end
  end
end
