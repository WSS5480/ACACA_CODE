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

  # POST /api/risk_engine/recalc_credit   body: { user_ids: [..]? }
  # Re-evalua el credito de clientes (todos o seleccionados) con la version ACTIVA
  # del motor de riesgo, respetando el credito ya utilizado.
  def recalc_credit
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff?

    scope = User.joins(:role).includes(:credit).where(roles: { name: 'cliente' })
    if params[:user_ids].present?
      ids = Array(params[:user_ids]).map(&:to_i).reject(&:zero?)
      scope = scope.where(id: ids)
    end

    active_v = RiskEngineConfig.active_version
    has_limit = Credit.column_names.include?('credit_limit')
    count = 0

    scope.find_each do |u|
      new_limit = u.calculate_initial_credit.to_f.round(2)
      credit = u.credit || u.build_credit(amount: new_limit)
      old_limit = (has_limit && credit.credit_limit) ? credit.credit_limit.to_f : credit.amount.to_f
      used = [(old_limit - credit.amount.to_f), 0].max
      new_amount = [(new_limit - used), 0].max.round(2)
      credit.amount = new_amount
      credit.credit_limit = new_limit if has_limit
      credit.save!
      u.update_column(:risk_version, active_v) if User.column_names.include?('risk_version')
      count += 1
    end

    render json: { ok: true, count: count, active_version: active_v }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def staff?
    %w[master admin].include?(@current_user&.role&.name)
  end


  def config_param
    raw = params[:config]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
  end

  def serialize(cfg)
    { version: cfg.version, notes: cfg.notes, config: cfg.config, active: cfg.active, created_at: cfg.created_at }
  end
end
