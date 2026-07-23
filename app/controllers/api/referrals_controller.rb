class Api::ReferralsController < ApplicationController
  include ClientOrTokenAuthenticatable
  include Paginatable

  # Nivel 3: Cliente o JWT para todas las acciones
  before_action :authenticate_client_or_user!
  before_action :set_referral, only: [:show, :update, :destroy]
  before_action :authorize_client_own_referral, only: [:index, :show, :update, :destroy]

  # GET /api/referrals
  def index
    referrals = current_user_referrals
    render_paginated(referrals, ReferralSerializer)
  end

  # GET /api/referrals/:id
  def show
    render json: ReferralSerializer.new(@referral).serializable_hash, status: :ok
  end

  # POST /api/referrals
  def create
    @referral = Referral.new(referral_params)

    # Si la autenticación es por ClientNumber, verificar que la orden pertenezca al cliente
    if authenticated_by_client_number?
      order = Order.find_by(id: referral_params[:order_id])
      unless order && order.user_id == @current_user.id
        return render json: { error: 'No autorizado para crear referencia en esta orden' }, status: :forbidden
      end
    end

    if @referral.save
      render json: ReferralSerializer.new(@referral).serializable_hash, status: :created
    else
      render json: { errors: @referral.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/referrals/:id
  def update
    if @referral.update(referral_params.except(:order_id))
      render json: ReferralSerializer.new(@referral).serializable_hash, status: :ok
    else
      render json: { errors: @referral.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/referrals/:id
  def destroy
    @referral.destroy
    head :no_content
  end

  private

  def set_referral
    @referral = Referral.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Referencia no encontrada' }, status: :not_found
  end

  def current_user_referrals
    if authenticated_by_client_number?
      # Clientes solo ven referencias de sus propias órdenes
      Referral.joins(:order).where(orders: { user_id: @current_user.id })
    else
      # Usuarios JWT (admin/master) pueden ver todas las referencias
      Referral.all
    end
  end

  def authorize_client_own_referral
    # Si la autenticación fue por ClientNumber, verificar que solo acceda a referencias de sus propias órdenes
    return unless authenticated_by_client_number?

    # Para index, ya se filtra en current_user_referrals
    return if action_name == 'index'

    # Para show, update, destroy verificar que la referencia pertenezca a una orden del cliente
    return if @referral.order&.user_id == @current_user.id

    render json: { error: 'No autorizado para acceder a esta referencia' }, status: :forbidden
  end

  def referral_params
    params.require(:referral).permit(
      :order_id,
      :nationality,
      :name,
      :last_name,
      :phone,
      :phone_work
    )
  end
end

