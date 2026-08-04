# frozen_string_literal: true

module Api
  class PasswordsController < ApplicationController
    include TokenAuthenticatable
    skip_before_action :authenticate_entity!

    RESET_VALIDITY = 2.hours

    # POST /api/passwords/forgot  { email }
    # Siempre responde 200 para no revelar si el correo existe.
    def forgot
      user = User.find_by('lower(email) = ?', params[:email].to_s.strip.downcase)
      if user
        token = SecureRandom.hex(24)
        user.update_columns(reset_password_token: token, reset_password_sent_at: Time.current)
        begin
          UserMailer.with(user: user, token: token).send_password_reset.deliver_now
        rescue StandardError => e
          Rails.logger.error "No se pudo enviar el correo de restablecimiento a #{user.email}: #{e.message}"
        end
      end
      render json: { ok: true }, status: :ok
    end

    # POST /api/passwords/reset  { token, password, password_confirmation }
    def reset
      token = params[:token].to_s.strip
      if token.blank?
        return render json: { error: 'Enlace inválido. Solicita uno nuevo.' }, status: :unprocessable_entity
      end

      user = User.find_by(reset_password_token: token)
      if user.nil? || user.reset_password_sent_at.nil? || user.reset_password_sent_at < RESET_VALIDITY.ago
        return render json: { error: 'El enlace ya no es válido o expiró. Solicita uno nuevo.' }, status: :unprocessable_entity
      end

      user.password = params[:password]
      user.password_confirmation = params[:password_confirmation]
      if user.save
        user.update_columns(reset_password_token: nil, reset_password_sent_at: nil)
        render json: { ok: true }, status: :ok
      else
        render json: { error: user.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end
  end
end
