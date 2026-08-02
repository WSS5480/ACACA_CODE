# frozen_string_literal: true

module Api
  class VerificationsController < ApplicationController
    include TokenAuthenticatable
    skip_before_action :authenticate_entity!

    # GET /api/verifications/status?email=...  -> { confirmed: bool }
    # La pantalla de registro consulta esto hasta que el cliente nos escribe por WhatsApp.
    def status
      user =
        if params[:email].present?
          User.find_by('lower(email) = ?', params[:email].to_s.strip.downcase)
        elsif params[:number].present?
          User.find_by(number: params[:number])
        end
      return render(json: { error: 'No encontrado' }, status: :not_found) unless user
      render json: { confirmed: user.confirmed? }, status: :ok
    end
  end
end
