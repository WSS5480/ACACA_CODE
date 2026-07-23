class Api::RiskEngineConfigsController < ApplicationController
  include TokenAuthenticatable

  before_action :authenticate_entity!

  # GET /api/risk_engine/versions
  def index
    render json: {
      active_version: RiskEngineConfig.active_version,
      versions: RiskEngineConfig.order(version: :desc).map { |c| serialize(c) }
    }, status: :ok
  end

  # POST /api/risk_engine/versions   body: { notes: "...", config: {...} }
  # Guarda una NUEVA versión (conservando las anteriores) y la deja activa.
  def create
    cfg = RiskEngineConfig.new(
      version: RiskEngineConfig.next_version,
      notes: params[:notes],
      config: config_param,
      active: true
    )

    if cfg.save
      render json: serialize(cfg), status: :created
    else
      render json: { errors: cfg.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/risk_engine/versions/:version/activate  (revertir a una versión previa)
  def activate
    cfg = RiskEngineConfig.find_by(version: params[:version])
    return render json: { error: 'Versión no encontrada' }, status: :not_found unless cfg

    cfg.update!(active: true)
    render json: serialize(cfg), status: :ok
  end

  private

  def config_param
    raw = params[:config]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
  end

  def serialize(cfg)
    { version: cfg.version, notes: cfg.notes, config: cfg.config, active: cfg.active, created_at: cfg.created_at }
  end
end
