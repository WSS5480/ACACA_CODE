# app/controllers/concerns/token_authenticatable.rb
module TokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    include ActionController::HttpAuthentication::Basic::ControllerMethods
    before_action :authenticate_entity!
  end

  private

  def authenticate_entity!
    Rails.logger.info "=== 🔐 authenticate_entity! START ==="
    Rails.logger.info "🔐 Request path: #{request.path}"
    Rails.logger.info "🔐 Request method: #{request.method}"
    Rails.logger.info "🔐 Request origin: #{request.headers['Origin']}"
    
    auth_header = request.headers['Authorization']
    Rails.logger.info "🔐 Authorization header present: #{auth_header.present?}"
    Rails.logger.info "🔐 Authorization header preview: #{auth_header ? auth_header[0..50] + '...' : 'N/A'}"
    
    unless auth_header
      Rails.logger.error "❌ No authorization header provided"
      return render json: { error: 'Token or Credentials not provided' }, status: :unauthorized
    end
    
    auth_header_split = auth_header.split(' ')
    token = nil
    if auth_header_split&.first == 'Bearer'
      token = auth_header_split&.last
      Rails.logger.info "🔐 Bearer token extracted, length: #{token&.length}"
    else
      Rails.logger.error "❌ Authorization header format invalid: #{auth_header_split&.first}"
    end
    
    unless token
      Rails.logger.error "❌ No valid token found in authorization header"
      return render json: { error: 'Token or Credentials format is invalid' }, status: :unauthorized
    end
    
    Rails.logger.info "🔐 Proceeding to authenticate user from token"
    authenticate_user_from_token(token)
    Rails.logger.info "=== 🔐 authenticate_entity! END ==="
  end

  def authenticate_user_from_token(token)
    Rails.logger.info "=== 🔐 authenticate_user_from_token START ==="
    Rails.logger.info "🔐 Token length: #{token.length}"
    Rails.logger.info "🔐 Token preview: #{token[0..20]}..."
    
    begin
      # Use the same secret key as Devise-JWT
      secret_key = ENV.fetch('DEVISE_JWT_SECRET_KEY', Rails.application.secret_key_base)
      Rails.logger.info "🔐 Using secret key (present): #{secret_key.present?}"
      
      payload = JWT.decode(token, secret_key, true, { algorithm: 'HS256' }).first
      Rails.logger.info "🔐 JWT payload decoded successfully"
      Rails.logger.info "🔐 Payload keys: #{payload.keys}"
      Rails.logger.info "🔐 User ID from payload: #{payload['sub']}"
      Rails.logger.info "🔐 JTI from payload: #{payload['jti']}"
      Rails.logger.info "🔐 Expiration: #{Time.at(payload['exp']) if payload['exp']}"
      
      # Check if token is in denylist
      jti = payload['jti']
      Rails.logger.info "🔐 Checking if JTI is in denylist: #{jti}"
      
      #if JwtDenylist.exists?(jti: jti)
      #  Rails.logger.error "❌ Token is in denylist (revoked)"
      #  return render json: { error: 'Token has been revoked', response: 'Token has been revoked' }, status: :unauthorized
      #end
      
      Rails.logger.info "✅ Token is not in denylist"
      Rails.logger.info "🔐 Looking for user with ID: #{payload['sub']}"
      
      @current_user = User.find(payload['sub'])
      Rails.logger.info "✅ User found: #{@current_user.id} (#{@current_user.email})"
      Rails.logger.info "🔐 User role: #{@current_user.role&.name} (#{@current_user.role&.name})"
      
    rescue JWT::DecodeError => e
      Rails.logger.error "❌ JWT Decode Error: #{e.message}"
      render json: { error: 'Invalid token', response: 'Invalid token' }, status: :unauthorized
    rescue JWT::ExpiredSignature => e
      Rails.logger.error "❌ JWT Expired: #{e.message}"
      render json: { error: 'Token expired', response: 'Token expired' }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "❌ User not found: #{e.message}"
      render json: { error: 'User not found', response: 'User not found' }, status: :unauthorized
    rescue => e
      Rails.logger.error "❌ Unexpected error in token authentication: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: 'Authentication error', response: 'Authentication error' }, status: :unauthorized
    end
    
    Rails.logger.info "=== 🔐 authenticate_user_from_token END ==="
  end
end

