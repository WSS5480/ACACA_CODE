class Api::OrdersController < ApplicationController
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable
  include DateFilterable

  # Desactivar autenticación por defecto
  skip_before_action :authenticate_client_or_user!
  # Nivel 3: Cliente o JWT para todas las acciones
  before_action :authenticate_client_or_user!
  # Permitir acceso sin autenticación a simulate_payment_plans
  skip_before_action :authenticate_client_or_user!, only: [:simulate_payment_plans, :dashboard]
  # Autenticación solo por JWT para dashboard
  before_action :authenticate_jwt_only!, only: [:dashboard]
  # Otros callbacks
  before_action :set_order, only: [:show, :update, :destroy, :assign_beneficiary]
  before_action :authorize_client_own_order, only: [:index, :show, :update, :destroy, :assign_beneficiary]

  # GET /api/orders
  def index
    orders = current_user_orders
    orders = apply_search_filter(orders, columns: %w[user_name user_last_name user_email product_title product_asin])
    orders = apply_status_filter(orders)
    orders = apply_date_filter(orders)
    render_paginated(orders, OrderSerializer)
  rescue DateFilterable::InvalidDateFormatError => e
    render json: { error: e.message }, status: :bad_request
  end

  # GET /api/orders/:id
  # POST /api/orders/:id/verify  (solo staff)
  # { beneficiary_verified, beneficiary_comment, buyer_verified, buyer_comment,
  #   references_verified, references_comment, admin_approved }
  def verify
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff_user?

    order = Order.find_by(id: params[:id])
    return render(json: { error: 'Orden no encontrada' }, status: :not_found) unless order

    fields = {}
    %w[beneficiary_verified buyer_verified references_verified residency_verified employment_verified admin_approved].each do |f|
      fields[f] = ActiveModel::Type::Boolean.new.cast(params[f]) if params.key?(f) && order.respond_to?(f)
    end
    %w[beneficiary_comment buyer_comment references_comment residency_comment employment_comment].each do |f|
      fields[f] = params[f].to_s if params.key?(f) && order.respond_to?(f)
    end
    if fields.key?('admin_approved')
      fields['approved_at'] = fields['admin_approved'] ? Time.current : nil
    end
    # ¿Es una aprobación NUEVA? (antes no estaba aprobada) -> avisar al cliente por WhatsApp.
    newly_approved = fields['admin_approved'] == true &&
                     !(order.respond_to?(:admin_approved) && order.admin_approved)
    order.update!(fields)
    # La verificación es de las PERSONAS de la compra (comprador, beneficiario, referencias),
    # no del artículo: se aplica a TODOS los artículos del mismo contrato (una sola verificación
    # por compra, un solo número de pedido/contrato).
    if order.contract_id.present? && fields.any?
      Order.where(contract_id: order.contract_id).where.not(id: order.id).find_each do |sibling|
        sibling.update!(fields)
      end
    end
    if fields.any?
      if fields['admin_approved'] == true
        AuditLog.record!(actor: @current_user, action: 'order_approved', target: order,
                         label: audit_order_label(order),
                         details: 'Aprobada para compra en Amazon (verificación completa)')
      else
        checks = fields.slice('beneficiary_verified', 'buyer_verified', 'references_verified')
                       .map { |k, v| "#{k.sub('_verified', '')}: #{v ? '✓' : '✗'}" }
        AuditLog.record!(actor: @current_user, action: 'order_verified', target: order,
                         label: audit_order_label(order),
                         details: (checks.any? ? "Verificación guardada · #{checks.join(' · ')}" : 'Verificación guardada'))
      end
    end
    notify_account_approved(order) if newly_approved
    render json: OrderSerializer.new(order.reload).serializable_hash, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/orders/:id/confirm_delivery  (solo staff)
  def confirm_delivery
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff_user?

    order = Order.find_by(id: params[:id])
    return render(json: { error: 'Orden no encontrada' }, status: :not_found) unless order
    return render(json: { error: 'La orden debe estar aprobada primero' }, status: :unprocessable_entity) unless order.respond_to?(:admin_approved) && order.admin_approved

    order.update!(delivered_at: Time.current)
    AuditLog.record!(actor: @current_user, action: 'order_delivered', target: order,
                     label: audit_order_label(order),
                     details: "Entrega confirmada · #{order.product_title.to_s[0, 80]}")
    render json: OrderSerializer.new(order.reload).serializable_hash, status: :ok
  end

  def show
    response = OrderSerializer.new(@order).serializable_hash

    # Los datos de la compra (comprador, aval, referencias, beneficiario) se capturan UNA sola vez
    # por contrato y viven en una de las órdenes hermanas (la primera): resolverlos desde
    # CUALQUIER orden del grupo, sin importar cuál se abra en la verificación.
    siblings = if @order.contract_id.present?
                 Order.where(contract_id: @order.contract_id).order(:id).includes(:buyer, :guarantor, :referrals, :beneficiary).to_a
               else
                 [@order]
               end
    buyer = (@order.respond_to?(:buyer) ? @order.buyer : nil) ||
            siblings.filter_map { |s| s.respond_to?(:buyer) ? s.buyer : nil }.first
    beneficiary = @order.beneficiary || siblings.filter_map(&:beneficiary).first
    guarantor = (@order.respond_to?(:guarantor) ? @order.guarantor : nil) ||
                siblings.filter_map { |s| s.respond_to?(:guarantor) ? s.guarantor : nil }.first
    referrals = @order.referrals.presence || siblings.map(&:referrals).find(&:present?) || []

    response[:data][:beneficiary] = beneficiary ? BeneficiarySerializer.new(beneficiary).serializable_hash[:data][:attributes] : nil
    response[:data][:buyer] = buyer ? BuyerSerializer.new(buyer).serializable_hash[:data][:attributes] : nil
    response[:data][:guarantor] = guarantor ? GuarantorSerializer.new(guarantor).serializable_hash[:data][:attributes] : nil
    response[:data][:referrals] = referrals.map { |referral| ReferralSerializer.new(referral).serializable_hash[:data][:attributes] }

    # Alertas de dirección: el CP debe corresponder a la ciudad/estado capturados (datos reales).
    response[:data][:address_alerts] = address_alerts_for(@order, buyer: buyer, beneficiary: beneficiary)

    # COMUNICACIONES POR REFERENCIA: estado y respuestas de la entrevista de
    # CADA referencia / contacto de domicilio / trabajo — se muestran BAJO cada
    # persona en la verificación (no en un área general).
    if defined?(ReferencePing) && ReferencePing.table_exists? && @order.contract_id.present?
      response[:data][:reference_checks] = ReferencePing.where(contract_id: @order.contract_id).order(:id).map do |p|
        ans = begin
          JSON.parse(p.answers.to_s)
        rescue StandardError
          []
        end
        { kind: p.target_kind, phone: p.phone, name: p.ref_name, status: p.status,
          survey_state: (p.respond_to?(:survey_state) ? p.survey_state : nil),
          recommends: (p.respond_to?(:recommends) ? p.recommends : nil),
          time_known: (p.respond_to?(:time_known) ? p.time_known : nil),
          answers: (ans.is_a?(Array) ? ans : []), sent_at: p.sent_at }
      end
    end

    render json: response, status: :ok
  end

  # POST /api/orders
  def create
    @order = Order.new(order_params)

    # Validar que el usuario y el producto existan
    order_user = acting_as_client? ? @current_user : User.find_by(id: order_params[:user_id])
    unless order_user
      return render json: { error: 'Usuario no encontrado' }, status: :not_found
    end
    order_product = Product.find_by(id: order_params[:product_id])
    unless order_product
      return render json: { error: 'Producto no encontrado' }, status: :not_found
    end

    # SINGLE SOURCE OF TRUTH: total = costo x turns x factor. used_credit = monto financiado.
    current_credit = order_user.credit_amount
    total = order_product.total_price
    down = order_params[:downpayment].to_f
    used = order_params[:used_credit].to_f
    # El crédito usado (financiado) no puede exceder el crédito disponible
    if current_credit < used
      return render json: { error: 'El usuario no tiene suficiente crédito' }, status: :unprocessable_entity
    end
    # Enganche + crédito usado == total
    unless money_equal?(down + used, total)
      return render json: { error: 'La suma del enganche y el crédito usado debe ser igual al total del producto' }, status: :unprocessable_entity
    end

    # Asignar los valores a order
    @order.user_id = order_user.id
    @order.user_name = order_user.name
    @order.user_last_name = order_user.last_name
    @order.user_email = order_user.email
    @order.product_title = order_product.title
    @order.product_asin = order_product.asin
    @order.product_price = order_product.price
    @order.product_price_with_discount = order_product.price_with_discount
    @order.product_original_price = order_product.original_price
    @order.product_turns = order_product.turns
    @order.product_decimal_factor = order_product.decimal_factor

    # Calcular el pago semanal
    set_weekly_payment

    ActiveRecord::Base.transaction do
      @order.save!
      # Restar el crédito usado al crédito del usuario
      if @order.used_credit.to_f > 0 && order_user.credit.present?
        new_credit_amount = order_user.credit.amount - @order.used_credit
        order_user.credit.update!(amount: new_credit_amount)
      end
    end

    Mailing::NewOrderMailerJob.perform_async(@order.id)

    render json: OrderSerializer.new(@order).serializable_hash.merge(updated_credit_amount: order_user.credit_amount), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # PATCH/PUT /api/orders/:id
  def update
    previous_used_credit = @order.used_credit.to_f

    ActiveRecord::Base.transaction do
      @order.update!(order_params)

      # SEGURIDAD: los campos de precio SIEMPRE se toman del producto real,
      # nunca de lo que envie el cliente (evita bajar turns/price para pagar de menos).
      if @order.product.present?
        @order.product_price = @order.product.price
        @order.product_price_with_discount = @order.product.price_with_discount
        @order.product_original_price = @order.product.original_price
        @order.product_turns = @order.product.turns
        @order.product_decimal_factor = @order.product.decimal_factor
      end

      # SEGURIDAD: revalidar la invariante de dinero (enganche + credito usado == total).
      total = @order.product&.total_price.to_f
      unless money_equal?(@order.downpayment.to_f + @order.used_credit.to_f, total)
        @order.errors.add(:base, 'La suma del enganche y el credito usado debe ser igual al precio del producto')
        raise ActiveRecord::RecordInvalid, @order
      end

      set_weekly_payment
      @order.save!
      recalculate_user_credit(previous_used_credit)
    end

    render json: OrderSerializer.new(@order).serializable_hash.merge(updated_credit_amount: @order.user&.credit_amount), status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # DELETE /api/orders/:id
  def destroy
    @order.destroy
    head :no_content
  end

  # PUT /api/orders/:id/assign_beneficiary
  def assign_beneficiary
    beneficiary_id = params[:beneficiary_id]

    unless beneficiary_id.present?
      return render json: { error: 'El beneficiary_id es requerido' }, status: :bad_request
    end

    beneficiary = Beneficiary.find_by(id: beneficiary_id)

    unless beneficiary
      return render json: { error: 'Beneficiario no encontrado' }, status: :not_found
    end

    # Si la autenticación es por ClientNumber, validar que el beneficiario pertenezca al cliente
    if acting_as_client? && beneficiary.user_id != @current_user.id
      return render json: { error: 'No autorizado para asignar este beneficiario' }, status: :forbidden
    end

    if @order.update(beneficiary_id: beneficiary.id)
      render json: OrderSerializer.new(@order).serializable_hash, status: :ok
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/orders/dashboard
  def dashboard
    # Query base para clientes
    cliente_role = Role.find_by(name: 'cliente')
    clients_query = cliente_role ? User.where(role: cliente_role) : User.none
    clients_query = apply_date_filter(clients_query)
    clients_count = clients_query.count

    # Query base para prequalifications
    prequalifications_query = Order.where(status: %w[pending incomplete])
    prequalifications_query = apply_date_filter(prequalifications_query)
    prequalifications_count = prequalifications_query.count

    # Query base para orders
    orders_query = Order.where(status: %w[approved paid cancelled])
    orders_query = apply_date_filter(orders_query)
    orders_count = orders_query.count

    # Query base para credits: clientes con crédito de tienda disponible (> 0)
    credits_query = Credit.where('amount > 0')
    credits_query = apply_date_filter(credits_query)
    credits_count = credits_query.count

    render json: {
      data: {
        clients_count: clients_count,
        prequalifications_count: prequalifications_count,
        orders_count: orders_count,
        credits_count: credits_count
      }
    }, status: :ok
  rescue DateFilterable::InvalidDateFormatError => e
    render json: { error: e.message }, status: :bad_request
  end

  # GET /api/orders/simulate_payment_plans
  def simulate_payment_plans
    # Validar que los parámetros requeridos estén presentes
    required_params = [:product_id, :product_price, :downpayment, :used_credit]
    missing_params = required_params.select { |param| params[param].blank? }

    if missing_params.any?
      return render json: { error: "Parámetros requeridos faltantes: #{missing_params.join(', ')}" }, status: :bad_request
    end

    product_id = params[:product_id]
    product_price = params[:product_price].to_f
    downpayment = params[:downpayment].to_f
    used_credit = params[:used_credit].to_f

    # Validar que el producto exista
    product = Product.find_by(id: product_id)
    unless product
      return render json: { error: 'Producto no encontrado' }, status: :not_found
    end

    # Validar que product_price sea mayor a 0
    unless product_price > 0
      return render json: { error: 'El precio del producto debe ser mayor a 0' }, status: :unprocessable_entity
    end

    # SINGLE SOURCE OF TRUTH: todo se calcula desde el modelo (Total = costo x turns x factor).
    total = product.total_price
    min_down = product.min_downpayment
    downpayment = min_down if downpayment < min_down
    downpayment = total if downpayment > total

    payment_plans = product.available_payment_plans(downpayment)

    render json: {
      payment_plans: payment_plans,
      total: total,
      min_downpayment: min_down,
      downpayment: downpayment.round(2),
      financed: (total - downpayment).round(2)
    }, status: :ok
  end

  # Compara CP vs ciudad/estado del comprador (EUA) y del beneficiario (MX) contra datos reales.
  def address_alerts_for(order, buyer: nil, beneficiary: nil)
    alerts = []
    b_rec = buyer || (order.respond_to?(:buyer) ? order.buyer : nil)
    ben_rec = beneficiary || order.beneficiary
    if b_rec.present?
      b = b_rec
      r = ZipLookup.check(country: 'US', zip: b.living_zip_code, city: b.living_city, state: b.living_state)
      if r[:status] == 'mismatch'
        expected = [r[:expected_city], r[:expected_state]].compact.join(', ')
        entered  = [b.living_city, b.living_state].reject { |v| v.to_s.strip.empty? }.join(', ')
        alerts << { section: 'buyer', zip: b.living_zip_code, entered: entered, expected: expected,
                    message: "El ZIP #{b.living_zip_code} (EUA) corresponde a #{expected}, pero el cliente escribió: #{entered}." }
      end
    end
    if ben_rec.present?
      ben = ben_rec
      r = ZipLookup.check(country: 'MX', zip: ben.zip_code, city: ben.city, state: ben.state)
      if r[:status] == 'mismatch'
        expected = [r[:expected_city], r[:expected_state]].compact.join(', ')
        entered  = [ben.city, ben.state].reject { |v| v.to_s.strip.empty? }.join(', ')
        alerts << { section: 'beneficiary', zip: ben.zip_code, entered: entered, expected: expected,
                    message: "El CP #{ben.zip_code} (México) corresponde a #{expected}, pero se capturó: #{entered}." }
      end
    end
    alerts
  rescue StandardError => e
    Rails.logger.warn "[address_alerts] #{e.message}"
    []
  end

  private

  def staff_user?
    %w[master admin].include?(@current_user&.role&.name)
  end

  # 🎉 CUENTA APROBADA: aviso automático por WhatsApp al cliente (en español).
  # Texto libre dentro de la ventana de 24 h; fuera de ella WhatsappOutbound lo
  # reenvía solo como plantilla 'cuenta_aprobada' (evento 'aprobada').
  def notify_account_approved(order)
    user = order.user
    return unless user&.phone.present?

    nombre = user.name.to_s.split.first.presence || 'cliente'
    # Texto EDITABLE en Configuración → Respuestas WhatsApp.
    texto = WaAutoText.render('aprobada', nombre: nombre)
    res = WhatsappOutbound.deliver(phone: user.phone, text: texto, event: 'aprobada',
                                   params: [nombre], user: user, actor: @current_user)
    ContactLog.create!(user_id: user.id, person_type: 'buyer',
                       person_name: [user.name, user.last_name].compact.join(' ').strip,
                       phone: user.phone, author_name: 'Automático',
                       body: res[:ok] ? "🤖 Aviso de cuenta APROBADA enviado por WhatsApp (#{res[:via]})" : "🤖 Aviso de cuenta aprobada NO se pudo enviar: #{res[:error]}")
    WaAlert.notify("Aviso de cuenta aprobada (#{user.phone})", res[:error]) if !res[:ok] && defined?(WaAlert)
  rescue StandardError => e
    Rails.logger.warn "[notify_account_approved] #{e.message}"
  end

  # Etiqueta legible de la orden para la bitácora de auditoría.
  def audit_order_label(order)
    num = order.contract&.contract_number.presence ||
          (order.contract ? order.contract.order_ref : "Orden ##{order.id}")
    client = [order.user_name, order.user_last_name].compact.join(' ').strip
    client.present? ? "#{num} · #{client}" : num.to_s
  end

  # Compara dos montos monetarios de forma segura (evita errores de punto flotante).
  # Redondea a centavos y permite una diferencia menor a 1 centavo.
  def money_equal?(a, b)
    (a.to_d.round(2) - b.to_d.round(2)).abs < 0.01
  end

  def set_order
    @order = Order.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Orden no encontrada' }, status: :not_found
  end

  def current_user_orders
    if acting_as_client?
      # Clientes solo ven sus propias órdenes
      @current_user.orders.includes(product: { images_attachments: :blob })
    else
      # Usuarios JWT pueden ver todas las órdenes
      Order.includes(product: { images_attachments: :blob }).all
    end
  end

  def apply_status_filter(collection)
    return collection if params[:status].blank?

    collection.where(status: params[:status])
  end

  def authorize_client_own_order
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a sus propias órdenes
    return unless acting_as_client?

    # Para index, ya se filtra en current_user_orders
    return if action_name == 'index'

    # Para show, update, destroy verificar que la orden pertenezca al cliente
    return if @order.user_id == @current_user.id

    render json: { error: 'No autorizado para acceder a esta orden' }, status: :forbidden
  end

  def order_params
    params.require(:order).permit(
      :user_id,
      :product_id,
      :beneficiary_id,
      :user_name,
      :user_last_name,
      :user_email,
      :product_title,
      :product_asin,
      :product_price,
      :product_price_with_discount,
      :product_original_price,
      :product_turns,
      :product_decimal_factor,
      :used_credit,
      :downpayment,
      :weekly_payment,
      :credit_duration,
      :status,
      :hightouch_id,
      :waiver
    )
  end

  def recalculate_weekly_payment_if_needed
    pricing_fields_changed = @order.saved_change_to_product_price? ||
                             @order.saved_change_to_product_price_with_discount? ||
                             @order.saved_change_to_product_decimal_factor? ||
                             @order.saved_change_to_product_turns? ||
                             @order.saved_change_to_used_credit? ||
                             @order.saved_change_to_downpayment? ||
                             @order.saved_change_to_credit_duration?

    return unless pricing_fields_changed && @order.product_price.present?

    set_weekly_payment
  end

  # Retorna el precio efectivo de la orden:
  # - product_price_with_discount si está definido y es mayor a 0
  # - product_price en caso contrario
  def order_effective_price
    @order.product_price_with_discount.present? && @order.product_price_with_discount > 0 ? @order.product_price_with_discount : @order.product_price
  end

  def set_weekly_payment
    return if @order.product.blank?

    new_weekly_payment = @order.product.calculate_weekly_payment(
      weeks: @order.credit_duration,
      downpayment: @order.downpayment,
      product_cost_usd: order_effective_price,
      used_credit: @order.used_credit,
      turns: @order.product_turns,
      decimal_factor: @order.product_decimal_factor
    )

    if @order.new_record?
      @order.weekly_payment = new_weekly_payment
    else
      @order.update_column(:weekly_payment, new_weekly_payment)
    end
  end

  def recalculate_user_credit(previous_used_credit)
    return unless @order.user&.credit.present?

    new_used_credit = @order.used_credit.to_f
    credit_difference = new_used_credit - previous_used_credit

    return if credit_difference.zero?

    # Si la diferencia es positiva, restamos más crédito; si es negativa, devolvemos crédito
    new_credit_amount = @order.user.credit.amount - credit_difference
    @order.user.credit.update!(amount: new_credit_amount)
  end
end

