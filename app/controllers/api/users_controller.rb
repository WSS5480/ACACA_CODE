class Api::UsersController < ApplicationController
  include TokenAuthenticatable
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticaciones por defecto
  skip_before_action :authenticate_entity!
  skip_before_action :authenticate_client_or_user!
  # Nivel 2: Solo JWT para index, create, destroy
  before_action :authenticate_entity!, only: [:index, :create, :destroy, :set_credit]
  # Nivel 3: Cliente o JWT para show, update, current_user
  before_action :authenticate_client_or_user!, only: [:show, :update, :current_user]
  # Otros callbacks
  before_action :set_user, only: [:show, :update, :destroy]
  before_action :authorize_client_own_profile, only: [:show, :update]

  # GET /api/users  (solo staff)
  def index
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end
    users = User.includes(:role)
    users = users.joins(:role).where(roles: { name: params[:role] }) if params[:role].present?
    users = apply_search_filter(users, columns: %w[name last_name email number])
    render_paginated(users, UserSerializer)
  end

  # GET /api/users/:id
  def show
    render json: UserSerializer.new(@user).serializable_hash, status: :ok
  end

  # POST /api/users
  def create
    @user = User.new(user_params)

    if @user.save
      # Asegurarse de que usuarios no-clientes (admin, etc.) se confirman al crearse
      @user.confirm if @user.role&.name != 'cliente'
      render json: UserSerializer.new(@user).serializable_hash, status: :created
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/users/:id
  def update
    if @user.update(user_params)
      render json: UserSerializer.new(@user).serializable_hash, status: :ok
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/users/:id
  def destroy
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    ActiveRecord::Base.transaction do
      # Contratos primero (cascada pagos/cuotas), luego SUS ordenes (cascada comprador/aval/referencias).
      @user.contracts.find_each(&:destroy!) if @user.respond_to?(:contracts)
      @user.orders.find_each(&:destroy!)
      @user.destroy!
    end
    head :no_content
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/users/client_register
  def client_register
    client_role = Role.find_by(name: 'cliente')

    unless client_role
      return render json: { error: 'El rol de cliente no está configurado' }, status: :unprocessable_entity
    end

    @user = User.new(user_params)
    @user.role = client_role
    @user.number = generate_client_number
    # SEGURIDAD: el cliente define su propia contraseña (login por email + contraseña).
    if @user.password.blank?
      return render json: { error: 'La contraseña es requerida' }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      @user.save!
      # Guardar la versión del motor de riesgo usada para evaluar a este cliente.
      @user.update_column(:risk_version, @user.risk_engine_version) if User.column_names.include?('risk_version')
      initial_credit = @user.calculate_initial_credit
      credit_attrs = { amount: initial_credit }
      credit_attrs[:credit_limit] = initial_credit if Credit.column_names.include?('credit_limit')
      @user.create_credit!(credit_attrs)
    end

    # Token de verificacion por WhatsApp (se incrusta en el enlace/QR que el cliente nos envia).
    # Defensivo: si algo falla aqui (p.ej. la columna aun no migro), NO debe impedir crear la cuenta.
    begin
      @user.ensure_whatsapp_verify_token!
    rescue StandardError => wa_token_error
      Rails.logger.error "No se pudo generar el token de WhatsApp: #{wa_token_error.message}"
    end

    # Correo de bienvenida (solo bienvenida).
    if @user.email.present?
      begin
        UserMailer.with(user: @user).send_client_welcome.deliver_now
      rescue StandardError => mail_error
        Rails.logger.error "Error enviando correo de bienvenida: #{mail_error.message}"
      end
    end

    # Sin WhatsApp configurado (sin numero de negocio) activamos la cuenta para no bloquear el acceso.
    unless ENV['WHATSAPP_BUSINESS_NUMBER'].present?
      @user.update_column(:confirmed_at, Time.current)
    end

    render json: UserSerializer.new(@user).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # GET /api/current_user
  def current_user
    render json: UserSerializer.new(@current_user).serializable_hash, status: :ok
  end

  # POST /api/users/:id/set_credit  { amount }
  # Herramienta de PRUEBAS (solo staff): fija la linea de credito (disponible = limite).
  def set_credit
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless %w[master admin].include?(@current_user&.role&.name)

    user = User.find_by(id: params[:id])
    return render(json: { error: 'Usuario no encontrado' }, status: :not_found) unless user

    amt = params[:amount].to_f
    return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if amt < 0

    cr = user.credit || user.build_credit(amount: 0)
    cr.amount = amt.round(2)
    cr.credit_limit = amt.round(2) if Credit.column_names.include?('credit_limit')
    cr.save!
    render json: { ok: true, credit_amount: cr.amount, credit_limit: (cr.respond_to?(:credit_limit) ? cr.credit_limit : cr.amount) }, status: :ok
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Usuario no encontrado' }, status: :not_found
  end

  def authorize_client_own_profile
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a su propio perfil
    return unless acting_as_client?
    return if @user.number == request.headers['ClientNumber']

    render json: { error: 'No autorizado para ver este perfil' }, status: :forbidden
  end

  def user_params
    params.require(:user).permit(
      :email,
      :password,
      :password_confirmation,
      :name,
      :last_name,
      :phone,
      :housing_type,
      :months_usa,
      :months_address,
      :months_job,
      :estimated_income,
      :delivery_country,
      :shared_income
    )
  end

  def generate_client_number
    max_attempts = 100
    attempts = 0

    loop do
      attempts += 1
      number = rand(100000..999999).to_s

      return number unless User.exists?(number: number)

      if attempts >= max_attempts
        raise StandardError, "No se pudo generar un número de cliente único después de #{max_attempts} intentos"
      end
    end
  end
end

