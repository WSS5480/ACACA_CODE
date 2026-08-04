class Api::UsersController < ApplicationController
  include TokenAuthenticatable
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticaciones por defecto
  skip_before_action :authenticate_entity!
  skip_before_action :authenticate_client_or_user!
  # Nivel 2: Solo JWT para index, create, destroy
  before_action :authenticate_entity!, only: [:index, :create, :destroy, :set_credit, :send_password_setup]
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

  # POST /api/users  (alta de usuarios del equipo — solo master/admin)
  def create
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    role = params[:user] && params[:user][:role_id].present? ? Role.find_by(id: params[:user][:role_id]) : nil
    if role&.name == 'master' && @current_user&.role&.name != 'master'
      return render json: { error: 'Solo master puede crear usuarios master' }, status: :forbidden
    end

    @user = User.new(user_params)
    @user.role = role if role

    # Sin contraseña capturada: se genera una aleatoria y el usuario crea la suya
    # con el enlace que le llega por correo (mismo flujo que "olvidé mi contraseña").
    generated = @user.password.blank?
    if generated
      tmp = SecureRandom.hex(16)
      @user.password = tmp
      @user.password_confirmation = tmp
    end

    if @user.save
      # Asegurarse de que usuarios no-clientes (admin, etc.) se confirman al crearse
      @user.confirm if @user.role&.name != 'cliente'
      send_password_setup_email(@user) if generated
      render json: UserSerializer.new(@user).serializable_hash, status: :created
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/users/:id/send_password_setup  — envía enlace para crear/cambiar contraseña
  def send_password_setup
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end
    user = User.find(params[:id])
    send_password_setup_email(user)
    render json: { ok: true }, status: :ok
  end

  # PATCH/PUT /api/users/:id
  def update
    if params[:user] && params[:user][:role_id].present?
      unless %w[master admin].include?(@current_user&.role&.name)
        return render json: { error: 'Solo un administrador puede cambiar roles' }, status: :forbidden
      end
      new_role = Role.find_by(id: params[:user][:role_id])
      if (new_role&.name == 'master' || @user.role&.name == 'master') && @current_user&.role&.name != 'master'
        return render json: { error: 'Solo master puede asignar o modificar el rol master' }, status: :forbidden
      end
      @user.role = new_role if new_role
    end

    if @user.update(user_params)
      render json: UserSerializer.new(@user).serializable_hash, status: :ok
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/users/:id
  def destroy
    role = @current_user&.role&.name
    unless %w[master admin sistema editor operador].include?(role)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    contracts = @user.respond_to?(:contracts) ? @user.contracts.to_a : []
    # Un contrato esta ENTREGADO si alguna de sus ordenes ya se entrego.
    delivered = contracts.select do |c|
      c.orders.any? { |o| o.respond_to?(:delivered_at) && o.delivered_at.present? }
    end

    # Con contratos entregados, borrar cliente+contratos exige credenciales de ADMIN.
    if delivered.any? && !%w[master admin].include?(role)
      return render json: {
        error: "Este cliente tiene #{delivered.size} contrato(s) ENTREGADO(s). Solo un administrador puede eliminarlo."
      }, status: :forbidden
    end

    ActiveRecord::Base.transaction do
      # Contratos primero (cascada pagos/cuotas), luego SUS ordenes (cascada comprador/aval/referencias).
      contracts.each(&:destroy!)
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

  # Genera token de restablecimiento y envía el correo para crear contraseña propia.
  def send_password_setup_email(user)
    token = SecureRandom.hex(24)
    user.update_columns(reset_password_token: token, reset_password_sent_at: Time.current)
    UserMailer.with(user: user, token: token).send_password_reset.deliver_now
  rescue StandardError => e
    Rails.logger.error "No se pudo enviar el correo de contraseña a #{user.email}: #{e.message}"
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

