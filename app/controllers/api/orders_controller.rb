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
  def show
    response = OrderSerializer.new(@order).serializable_hash
    
    # Agregar información del beneficiario al mismo nivel que attributes
    if @order.beneficiary.present?
      response[:data][:beneficiary] = BeneficiarySerializer.new(@order.beneficiary).serializable_hash[:data][:attributes]
    else
      response[:data][:beneficiary] = nil
    end
    # Agregar información del comprador al mismo nivel que attributes
    if @order.buyer.present?
      response[:data][:buyer] = BuyerSerializer.new(@order.buyer).serializable_hash[:data][:attributes]
    else
      response[:data][:buyer] = nil
    end
    # Agregar información del aval al mismo nivel que attributes
    if @order.guarantor.present?
      response[:data][:guarantor] = GuarantorSerializer.new(@order.guarantor).serializable_hash[:data][:attributes]
    else
      response[:data][:guarantor] = nil
    end
    # Agregar información de los referidos al mismo nivel que attributes
    if @order.referrals.present?
      response[:data][:referrals] = @order.referrals.map do |referral|
        ReferralSerializer.new(referral).serializable_hash[:data][:attributes]
      end
    else
      response[:data][:referrals] = []
    end
    
    render json: response, status: :ok
  end

  # POST /api/orders
  def create
    @order = Order.new(order_params)

    # Validar que el usuario y el producto existan
    order_user = authenticated_by_client_number? ? @current_user : User.find_by(id: order_params[:user_id])
    unless order_user
      return render json: { error: 'Usuario no encontrado' }, status: :not_found
    end
    order_product = Product.find_by(id: order_params[:product_id])
    unless order_product
      return render json: { error: 'Producto no encontrado' }, status: :not_found
    end

    # Usar precio efectivo (price_with_discount si está definido y > 0, sino price)
    current_credit = order_user.credit_amount
    effective_price = order_product.effective_price
    price_to_pay = effective_price - order_params[:downpayment].to_f
    # Validar que el usuario tenga suficiente crédito
    if current_credit < price_to_pay || current_credit < order_params[:used_credit].to_f
      return render json: { error: 'El usuario no tiene suficiente crédito' }, status: :unprocessable_entity
    end

    # Validar que la suma de downpayment y used_credit no sea menor al precio del producto
    unless money_equal?(order_params[:downpayment].to_f + order_params[:used_credit].to_f, effective_price)
      return render json: { error: 'La suma de downpayment y used_credit no puede ser diferente al precio del producto' }, status: :unprocessable_entity
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
      recalculate_weekly_payment_if_needed
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
    if authenticated_by_client_number? && beneficiary.user_id != @current_user.id
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

    # Usar precio efectivo (price_with_discount si está definido y > 0, sino price)
    effective_price = product.effective_price

    # Validar que product_price sea igual al precio efectivo del producto
    unless money_equal?(product_price, effective_price)
      return render json: { error: 'El precio del producto no coincide con el precio registrado' }, status: :unprocessable_entity
    end

    # Validar que la suma de downpayment y used_credit sea igual al precio efectivo
    unless money_equal?(downpayment + used_credit, effective_price)
      return render json: { error: 'La suma de downpayment y used_credit debe ser igual al precio del producto' }, status: :unprocessable_entity
    end

    # Calcular pagos semanales para los 4 plazos
    payment_plans = [52, 34, 26, 13].map do |weeks|
      weekly_payment = product.calculate_weekly_payment(
        weeks: weeks,
        downpayment: downpayment,
        product_cost_usd: effective_price,
        used_credit: used_credit
      )

      {
        weeks: weeks,
        weekly_payment: weekly_payment
      }
    end

    render json: { payment_plans: payment_plans }, status: :ok
  end

  private

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
    if authenticated_by_client_number?
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
    return unless authenticated_by_client_number?

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

