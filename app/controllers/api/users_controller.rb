class Api::UsersController < ApplicationController
  include TokenAuthenticatable
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticaciones por defecto
  skip_before_action :authenticate_entity!
  skip_before_action :authenticate_client_or_user!
  # Nivel 2: Solo JWT para index, create, destroy
  before_action :authenticate_entity!, only: [:index, :create, :destroy]
  # Nivel 3: Cliente o JWT para show, update, current_user
  before_action :authenticate_client_or_user!, only: [:show, :update, :current_user]
  # Otros callbacks
  before_action :set_user, only: [:show, :update, :destroy]
  before_action :authorize_client_own_profile, only: [:show, :update]

  # GET /api/users
  def index
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
    @user.destroy
    head :no_content
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
    @user.password = Devise.friendly_token[0, 20] # Generar una contraseña aleatoria que no será usada ya que el cliente se autoriza por su número y no la necesita

    ActiveRecord::Base.transaction do
      @user.save!
      # Guardar la versión del motor de riesgo usada para evaluar a este cliente.
      @user.update_column(:risk_version, @user.risk_engine_version) if User.column_names.include?('risk_version')
      @user.create_credit!(amount: @user.calculate_initial_credit)
    end

    # Generar token de confirmación y enviar correo de bienvenida con link de confirmación
    if @user.email.present?
      raw_token, encrypted_token = Devise.token_generator.generate(User, :confirmation_token)
      @user.confirmation_token = encrypted_token
      @user.confirmation_sent_at = Time.current
      @user.save(validate: false)

      begin
        UserMailer.with(user: @user, confirmation_token: raw_token).send_client_welcome.deliver_now
      rescue StandardError => mail_error
        Rails.logger.error "Error enviando correo de bienvenida: #{mail_error.message}"
      end
    else
      # Sin email: activar cuenta de inmediato para que pueda iniciar sesión por otros medios
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

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Usuario no encontrado' }, status: :not_found
  end

  def authorize_client_own_profile
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a su propio perfil
    return unless authenticated_by_client_number?
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
      :shared_income,
      :role_id
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

