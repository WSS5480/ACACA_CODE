class Api::BuyersController < ApplicationController
  include ClientOrTokenAuthenticatable
  include FillRecordFromUser
  include Paginatable

  # Nivel 3: Cliente o JWT para todas las acciones
  before_action :authenticate_client_or_user!
  before_action :set_buyer, only: [:show, :update, :destroy]
  before_action :authorize_client_own_buyer, only: [:index, :show, :update, :destroy]

  # GET /api/buyers
  def index
    buyers = current_user_buyers
    render_paginated(buyers, BuyerSerializer)
  end

  # GET /api/buyers/:id
  def show
    render json: BuyerSerializer.new(@buyer).serializable_hash, status: :ok
  end

  # POST /api/buyers
  def create
    @buyer = Buyer.new(buyer_params)

    # Si la autenticación es por ClientNumber, verificar que la orden pertenezca al cliente
    if authenticated_by_client_number?
      order = Order.find_by(id: buyer_params[:order_id])
      unless order && order.user_id == @current_user.id
        return render json: { error: 'No autorizado para crear comprador en esta orden' }, status: :forbidden
      end
    end

    fill_record_from_user(
      @buyer,
      %w[name last_name phone email housing_type months_usa months_address weekly_income:estimated_income]
    )

    if @buyer.save
      render json: BuyerSerializer.new(@buyer).serializable_hash, status: :created
    else
      render json: { errors: @buyer.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/buyers/:id
  def update
    if @buyer.update(buyer_params.except(:order_id))
      render json: BuyerSerializer.new(@buyer).serializable_hash, status: :ok
    else
      render json: { errors: @buyer.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/buyers/:id
  def destroy
    @buyer.destroy
    head :no_content
  end

  private

  def set_buyer
    @buyer = Buyer.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Comprador no encontrado' }, status: :not_found
  end

  def current_user_buyers
    if authenticated_by_client_number?
      # Clientes solo ven buyers de sus propias órdenes
      Buyer.joins(:order).where(orders: { user_id: @current_user.id })
    else
      # Usuarios JWT (admin/master) pueden ver todos los buyers
      Buyer.all
    end
  end

  def authorize_client_own_buyer
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a buyers de sus propias órdenes
    return unless authenticated_by_client_number?

    # Para index, ya se filtra en current_user_buyers
    return if action_name == 'index'

    # Para show, update, destroy verificar que el buyer pertenezca a una orden del cliente
    return if @buyer.order&.user_id == @current_user.id

    render json: { error: 'No autorizado para acceder a este comprador' }, status: :forbidden
  end

  def buyer_params
    params.require(:buyer).permit(
      :order_id,
      :name,
      :last_name,
      :nationality,
      :state_residence,
      :living_address1,
      :living_address2,
      :living_zip_code,
      :living_state,
      :living_city,
      :housing_type,
      :months_usa,
      :months_address,
      :job,
      :phone,
      :phone_work,
      :email,
      :weekly_income,
      :relationship_with_beneficiary,
      :delivery_address1,
      :delivery_address2,
      :delivery_zip_code,
      :delivery_state,
      :delivery_city,
      :phone_beneficiary,
      :identification,
      :proof_of_address,
      :proof_of_income
    )
  end
end

