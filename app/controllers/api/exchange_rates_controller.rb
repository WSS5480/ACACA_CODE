class Api::ExchangeRatesController < ApplicationController
  include TokenAuthenticatable
  include Paginatable

  before_action :set_exchange_rate, only: [:show, :destroy]

  # GET /api/exchange_rates
  def index
    exchange_rates = ExchangeRate.all
    render_paginated(exchange_rates, ExchangeRateSerializer)
  end

  # GET /api/exchange_rates/:id
  def show
    render json: ExchangeRateSerializer.new(@exchange_rate).serializable_hash, status: :ok
  end

  # POST /api/exchange_rates
  def create
    @exchange_rate = ExchangeRate.new(exchange_rate_params)

    if @exchange_rate.save
      render json: ExchangeRateSerializer.new(@exchange_rate).serializable_hash, status: :created
    else
      render json: { errors: @exchange_rate.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/exchange_rates/:id
  def destroy
    @exchange_rate.destroy
    head :no_content
  end

  private

  def set_exchange_rate
    @exchange_rate = ExchangeRate.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Tipo de cambio no encontrado' }, status: :not_found
  end

  def exchange_rate_params
    params.require(:exchange_rate).permit(:usd_to_mxn)
  end
end

