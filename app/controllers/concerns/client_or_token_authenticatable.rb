# app/controllers/concerns/client_or_token_authenticatable.rb
module ClientOrTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_client_or_user!
  end

  private

  # Autenticación solo por JWT para dashboard para el caso en que el controlador use este módulo y no el de TokenAuthenticatable
  def authenticate_jwt_only!
    # Rechazar autenticación por ClientNumber
    if request.headers['ClientNumber'].present?
      return render json: { error: 'Este endpoint requiere autenticación por token JWT' }, status: :unauthorized
    end

    # Reutilizar la lógica existente de autenticación JWT
    authenticate_by_jwt_token
  end

  def authenticate_client_or_user!
    client_number = request.headers['ClientNumber']

    # Si hay header de cliente, autenticar por número (no intentar JWT)
    if client_number.present?
      authenticate_by_client_number(client_number)
      return
    end

    # Si no hay número de cliente, intentar autenticación por JWT
    authenticate_by_jwt_token
  end

  def authenticate_by_client_number(client_number)
    @current_user = User.find_by(number: client_number)

    unless @current_user
      return render json: { error: 'Número de cliente inválido' }, status: :unauthorized
    end

    unless @current_user.confirmed?
      return render json: {
        error: 'Cuenta no confirmada. Debes hacer clic en el enlace de confirmación que te enviamos por email antes de acceder.'
      }, status: :forbidden
    end
  end

  def authenticate_by_jwt_token
    auth_header = request.headers['Authorization']

    unless auth_header
      return render json: { error: 'Se requiere autenticación: ClientNumber o Authorization token' }, status: :unauthorized
    end

    auth_header_split = auth_header.split(' ')
    token = auth_header_split.last if auth_header_split.first == 'Bearer'

    unless token
      return render json: { error: 'Formato de token inválido' }, status: :unauthorized
    end

    decode_jwt_token(token)
  end

  def decode_jwt_token(token)
    secret_key = ENV.fetch('DEVISE_JWT_SECRET_KEY', Rails.application.secret_key_base)
    payload = JWT.decode(token, secret_key, true, { algorithm: 'HS256' }).first

    @current_user = User.find(payload['sub'])
  rescue JWT::DecodeError
    render json: { error: 'Token inválido' }, status: :unauthorized
  rescue JWT::ExpiredSignature
    render json: { error: 'Token expirado' }, status: :unauthorized
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Usuario no encontrado' }, status: :unauthorized
  end

  # Helper para saber si la autenticación fue por ClientNumber
  def authenticated_by_client_number?
    request.headers['ClientNumber'].present?
  end
end
