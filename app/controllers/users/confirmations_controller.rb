# frozen_string_literal: true

class Users::ConfirmationsController < Devise::ConfirmationsController
  respond_to :json

  # GET /api/users/confirmation?confirmation_token=xxx
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])

    if resource.errors.empty?
      render json: {
        message: I18n.t('devise.confirmations.confirmed'),
        confirmed: true,
        client_number: resource.number,
        #user: UserSerializer.new(resource).serializable_hash[:data][:attributes]
      }, status: :ok
    else
      render json: {
        message: I18n.t('devise.confirmations.invalid_token'),
        errors: resource.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
end
