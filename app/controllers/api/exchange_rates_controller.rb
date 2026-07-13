class Api::ExchangeRatesController < ApplicationController
  include TokenAuthenticatable
  include Paginatable

  before_action :set_exchange_rate, only: [:show, :destroy]

  def index
    exchange_rates = ExchangeRate.all
    render_paginated(exchange_rates, ExchangeRateSerializer)
  end

  def show
    render json: ExchangeRateSerializer.new(@exchange_rate).serializable_hash, status: :ok
  end

  def create
    @exchange_rate = ExchangeRate.new(exchange_rate_params)

    if @exchange_rate.save
      render json: ExchangeRateSerializer.new(@exchange_rate).serializable_hash, status: :created
    else
      render json: { errors: @exchange_rate.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def refresh
    before = ExchangeRate.current_rate
    ExchangeRates::FetchRateJob.new.perform
    latest = ExchangeRate.order(created_at: :desc).first
    render json: {
      usd_to_mxn: (latest&.usd_to_mxn || before),
      updated: latest.present? && latest.usd_to_mxn.to_d != before.to_d,
      fetched_at: latest&.created_at
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message, usd_to_mxn: ExchangeRate.current_rate }, status: :ok
  end

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
