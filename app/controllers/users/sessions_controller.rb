# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  include RackSessionsFix
  respond_to :json

  # Sobrescribir create para permitir login con número de cliente (sin contraseña)
  def create
    # Si se envía número de cliente sin contraseña, autenticar directamente
    if params[:user] && params[:user][:number].present? && (params[:user][:password].blank? || params[:user][:password].nil?)
      user = User.joins(:role).find_by(number: params[:user][:number], roles: { name: 'cliente' })
      
      unless user
        return render json: {
          code: 401,
          message: 'Número de cliente inválido.',
          error: 'Número de cliente no encontrado'
        }, status: :unauthorized
      end

      unless user.confirmed?
        return render json: {
          code: 403,
          message: 'Debes confirmar tu correo antes de iniciar sesión.',
          error: 'Cuenta no confirmada. Revisa el enlace que te enviamos por email.'
        }, status: :forbidden
      end

      # Autenticar directamente sin contraseña para clientes
      # Usar warden para establecer la sesión y generar el token JWT
      warden.set_user(user, scope: :user)
      sign_in(resource_name, user)
      
      # El token JWT se genera automáticamente por devise-jwt después de sign_in
      yield user if block_given?
      respond_with user, location: after_sign_in_path_for(user)
      return
    end

    # Si se envía número de cliente con contraseña, usar flujo normal
    if params[:user] && params[:user][:number].present? && params[:user][:password].present?
      user = User.find_by(number: params[:user][:number])
      
      unless user
        return render json: {
          code: 401,
          message: 'Número de cliente inválido.',
          error: 'Número de cliente no encontrado'
        }, status: :unauthorized
      end

      # Usar el email del usuario encontrado para autenticación con contraseña
      params[:user][:email] = user.email
      params[:user].delete(:number)
    end

    # Continuar con el flujo normal de Devise (email + password)
    self.resource = warden.authenticate!(auth_options)
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  rescue => e
    Rails.logger.error "Login error: #{e.class} - #{e.message}"
    render json: {
      code: 401,
      message: 'Credenciales inválidas.',
      error: 'Email o contraseña incorrectos'
    }, status: :unauthorized
  end

  private

  def respond_with(current_user, _opts = {})
    res_data = UserSerializer.new(current_user).serializable_hash[:data][:attributes]
    
    # Generate JWT token
    token = request.env['warden-jwt_auth.token']
    Rails.logger.info "Generated JWT token for user #{current_user.email}: #{token.present? ? 'Present' : 'Missing'}"

    render json: {
      code: 200, 
      message: 'Logged in successfully.',
      data: { 
        user: res_data,
        token: token 
      }
    }, status: :ok
  end

  def respond_to_on_destroy
    if request.headers['Authorization'].present?
      jwt_payload = JWT.decode(request.headers['Authorization'].split(' ').last, ENV.fetch('SECRET_KEY_BASE', Rails.application.secret_key_base)).first
      current_user = User.find(jwt_payload['sub'])
    end
    
    if current_user
      render json: {
        status: 200,
        message: 'Logged out successfully.'
      }, status: :ok
    else
      render json: {
        status: 401,
        message: "Couldn't find an active session."
      }, status: :unauthorized
    end
  end
end

  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end