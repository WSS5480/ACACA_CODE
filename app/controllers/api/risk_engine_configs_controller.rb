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
    count = 0

    scope.find_each do |u|
      # Misma matemática que User#recalculate_credit! — y ahora con el
      # parentesco REAL del primer "quien recibe" (antes usaba el default).
      u.recalculate_credit!
      count += 1
    end

    render json: { ok: true, count: count, active_version: active_v }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/risk_engine/reference_findings — hallazgos del motor de decisión
  # (sombra) + contratos actualmente en HOLD/STOP para revisión humana.
  def reference_findings
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff?

    findings = begin
      JSON.parse(AppSetting.get(ReferenceGateReadiness::KEY).to_s)
    rescue StandardError
      nil
    end
    holds = []
    if defined?(ReferenceGate) && ReferenceGate.ready?
      holds = Contract.where(reference_gate_status: %w[hold stop])
                      .order(reference_gate_at: :desc).limit(50).map do |c|
        { id: c.id, ref: (c.contract_number.presence || (c.respond_to?(:order_ref) ? c.order_ref : nil) || "##{c.id}"),
          cliente: [c.user&.name, c.user&.last_name].compact.join(' '),
          estado: c.reference_gate_status, razones: c.reference_gate_reasons, desde: c.reference_gate_at }
      end
    end
    render json: { findings: findings, en_revision: holds, config: ReferenceGateReadiness.config }, status: :ok
  end

  # POST /api/risk_engine/reference_findings_run — recalcular AHORA (staff)
  def reference_findings_run
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless staff?
    return render(json: { error: 'El gate aún no tiene tablas (falta migrar)' }, status: :unprocessable_entity) unless defined?(ReferenceGate) && ReferenceGate.ready?

    render json: { ok: true, findings: ReferenceGateReadiness.evaluate! }, status: :ok
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
