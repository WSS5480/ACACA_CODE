class Api::ClientsController < ApplicationController
  include TokenAuthenticatable

  # Sin autenticación para forgot_number
  skip_before_action :authenticate_entity!, only: [:forgot_number]
  # Autenticación JWT requerida para update_credit
  before_action :authenticate_entity!, only: [:update_credit]
  before_action :set_client, only: [:update_credit]

  # POST /api/clients/forgot_number
  def forgot_number
    email = params[:email]&.downcase&.strip

    unless email.present?
      return render json: { error: 'El email es requerido' }, status: :bad_request
    end

    user = User.joins(:role).find_by(email: email, roles: { name: 'cliente' })

    if user.nil?
      # Por seguridad, no revelar si el email existe o no
      return render json: {
        message: 'Si existe una cuenta con ese email, recibirás tu número de cliente.'
      }, status: :ok
    end

    # Enviar email con número de cliente
    send_client_number_email(user)

    render json: {
      message: 'Si existe una cuenta con ese email, recibirás tu número de cliente.'
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error "Forgot client number error: #{e.message}"
    render json: { error: 'Ocurrió un error. Por favor intenta nuevamente.' }, status: :internal_server_error
  end

  # PATCH /api/clients/:id/credit
  def update_credit
    amount = params[:amount]

    unless amount.present?
      return render json: { error: 'El monto es requerido' }, status: :bad_request
    end

    credit = @client.credit || @client.build_credit
    credit.amount = amount

    if credit.save
      render json: UserSerializer.new(@client).serializable_hash, status: :ok
    else
      render json: { errors: credit.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Update credit error: #{e.message}"
    render json: { error: 'Ocurrió un error al actualizar el crédito.' }, status: :internal_server_error
  end

  private

  def set_client
    @client = User.joins(:role).find_by(id: params[:id], roles: { name: 'cliente' })

    unless @client
      render json: { error: 'Cliente no encontrado' }, status: :not_found
    end
  end

  def send_client_number_email(user)
    if Rails.env.development?
      Rails.logger.info "📧 Sending client number email synchronously (development mode)"
      UserMailer.with(user: user).send_client_number.deliver_now
    else
      Rails.logger.info "📧 Queueing client number email job (production mode)"
      Mailing::ClientNumberMailerJob.perform_async(user.id)
    end
  end
end

