class Users::PasswordsController < Devise::PasswordsController
  # POST /resource/password
  def create
    # Find user by email
    user = User.find_by(email: resource_params[:email])
    
    if user.nil?
      # User doesn't exist - return error
      render json: { status: 404, error: 'Email no encontrado.' }, status: :not_found
      return
    end
    
    # Send reset instructions
    if user.send_reset_password_instructions
      render json: { status: 200, message: 'Te hemos enviado un correo con instrucciones para restablecer tu contraseña.' }, status: :ok
    else
      render json: { status: 422, error: 'No se pudo enviar el correo de recuperación. Intenta nuevamente.' }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Password reset error: #{e.message}"
    render json: { status: 500, error: 'Ocurrió un error. Por favor intenta nuevamente.' }, status: :internal_server_error
  end

  # PUT /resource/password
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)
    
    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)
      if Devise.sign_in_after_reset_password
        resource.after_database_authentication
        sign_in(resource_name, resource)
      end
      render json: { status: 200, message: I18n.t('devise.passwords.updated') }, status: :ok
    else
      set_minimum_password_length
      if resource.errors.details[:reset_password_token]&.any? { |error| error[:error] == :invalid }
        render json: { status: 422, error: 'Token de reset de contraseña es inválido o ha expirado.' }, status: :unprocessable_entity
      else
        render json: { status: 422, errors: resource.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  protected

  # Customize this method as per your need
  def successfully_sent?(resource)
    notice = Devise.paranoid ? resource.errors.empty? : resource.errors[:email].empty?
    notice
  end

  private

  def resource_params
    params.require(:user).permit(:email, :password, :password_confirmation, :reset_password_token)
  end

  def resource_class
    User
  end
end
