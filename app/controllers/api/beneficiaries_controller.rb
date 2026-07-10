class Api::BeneficiariesController < ApplicationController
  include ClientOrTokenAuthenticatable
  include Paginatable

  # Nivel 3: Cliente o JWT para todas las acciones
  before_action :authenticate_client_or_user!
  before_action :set_beneficiary, only: [:show, :update, :destroy]
  before_action :authorize_client_own_beneficiary, only: [:index, :show, :update, :destroy]

  # GET /api/beneficiaries
  def index
    beneficiaries = current_user_beneficiaries
    render_paginated(beneficiaries, BeneficiarySerializer)
  end

  # GET /api/beneficiaries/:id
  def show
    render json: BeneficiarySerializer.new(@beneficiary).serializable_hash, status: :ok
  end

  # POST /api/beneficiaries
  def create
    @beneficiary = Beneficiary.new(beneficiary_params)

    # Si la autenticación es por ClientNumber, asignar el user_id del cliente autenticado
    if authenticated_by_client_number?
      @beneficiary.user_id = @current_user.id
    end

    if @beneficiary.save
      render json: BeneficiarySerializer.new(@beneficiary).serializable_hash, status: :created
    else
      render json: { errors: @beneficiary.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/beneficiaries/:id
  def update
    if @beneficiary.update(beneficiary_params)
      render json: BeneficiarySerializer.new(@beneficiary).serializable_hash, status: :ok
    else
      render json: { errors: @beneficiary.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/beneficiaries/:id
  def destroy
    @beneficiary.destroy
    head :no_content
  end

  private

  def set_beneficiary
    @beneficiary = Beneficiary.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Beneficiario no encontrado' }, status: :not_found
  end

  def current_user_beneficiaries
    if authenticated_by_client_number?
      # Clientes solo ven sus propios beneficiarios
      @current_user.beneficiaries
    else
      # Usuarios JWT pueden ver todos los beneficiarios
      Beneficiary.all
    end
  end

  def authorize_client_own_beneficiary
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a sus propios beneficiarios
    return unless authenticated_by_client_number?

    # Para index, ya se filtra en current_user_beneficiaries
    return if action_name == 'index'

    # Para show, update, destroy verificar que el beneficiario pertenezca al cliente
    return if @beneficiary.user_id == @current_user.id

    render json: { error: 'No autorizado para acceder a este beneficiario' }, status: :forbidden
  end

  def beneficiary_params
    params.require(:beneficiary).permit(
      :user_id,
      :name,
      :last_name,
      :email,
      :phone,
      :address1,
      :address2,
      :zip_code,
      :state,
      :city
    )
  end
end

