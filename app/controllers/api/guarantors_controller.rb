class Api::GuarantorsController < ApplicationController
  include ClientOrTokenAuthenticatable
  include Paginatable

  # Nivel 3: Cliente o JWT para todas las acciones
  before_action :authenticate_client_or_user!
  before_action :set_guarantor, only: [:show, :update, :destroy]
  before_action :authorize_client_own_guarantor, only: [:index, :show, :update, :destroy]

  # GET /api/guarantors
  def index
    guarantors = current_user_guarantors
    render_paginated(guarantors, GuarantorSerializer)
  end

  # GET /api/guarantors/:id
  def show
    render json: GuarantorSerializer.new(@guarantor).serializable_hash, status: :ok
  end

  # POST /api/guarantors
  def create
    @guarantor = Guarantor.new(guarantor_params)

    # Si la autenticación es por ClientNumber, verificar que la orden pertenezca al cliente
    if authenticated_by_client_number?
      order = Order.find_by(id: guarantor_params[:order_id])
      unless order && order.user_id == @current_user.id
        return render json: { error: 'No autorizado para crear aval en esta orden' }, status: :forbidden
      end
    end

    if @guarantor.save
      render json: GuarantorSerializer.new(@guarantor).serializable_hash, status: :created
    else
      render json: { errors: @guarantor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/guarantors/:id
  def update
    if @guarantor.update(guarantor_params.except(:order_id))
      render json: GuarantorSerializer.new(@guarantor).serializable_hash, status: :ok
    else
      render json: { errors: @guarantor.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/guarantors/:id
  def destroy
    @guarantor.destroy
    head :no_content
  end

  private

  def set_guarantor
    @guarantor = Guarantor.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Aval no encontrado' }, status: :not_found
  end

  def current_user_guarantors
    if authenticated_by_client_number?
      # Clientes solo ven garantes de sus propias órdenes
      Guarantor.joins(:order).where(orders: { user_id: @current_user.id })
    else
      # Usuarios JWT (admin/master) pueden ver todos los garantes
      Guarantor.all
    end
  end

  def authorize_client_own_guarantor
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a garantes de sus propias órdenes
    return unless authenticated_by_client_number?

    # Para index, ya se filtra en current_user_guarantors
    return if action_name == 'index'

    # Para show, update, destroy verificar que el garante pertenezca a una orden del cliente
    return if @guarantor.order&.user_id == @current_user.id

    render json: { error: 'No autorizado para acceder a este aval' }, status: :forbidden
  end

  def guarantor_params
    params.require(:guarantor).permit(
      :order_id,
      :name,
      :last_name,
      :address1,
      :address2,
      :zip_code,
      :state,
      :city,
      :phone,
      :email,
      :proof_of_address,
      :identification
    )
  end
end

