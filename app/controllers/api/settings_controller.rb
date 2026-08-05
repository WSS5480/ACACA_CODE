class Api::SettingsController < ApplicationController
  include TokenAuthenticatable

  # La lectura de tasas es PÚBLICA: la tienda la usa para calcular precios y pagos.
  skip_before_action :authenticate_entity!, only: [:rates], raise: false

  CONTRACT_KEY = 'contract_template'

  # GET /api/settings/rates  (público)
  # Tasas configurables + factores derivados de la tasa de interés:
  # factor de financiamiento = 1 + tasa/100 · factor de contado = 100/(100+tasa).
  def rates
    render json: {
      tax_rate: Product.tax_rate,
      interest_rate: Product.interest_rate,
      waiver_rate: Product.waiver_rate,
      mora_rate: Product.mora_rate,
      processing_fee: Product.processing_fee,
      cat_rate: Product.cat_rate,
      finance_factor: Product.finance_factor,
      cash_factor: Product.default_cash_factor
    }, status: :ok
  end

  # PUT /api/settings/rates { tax_rate, interest_rate, waiver_rate }  (solo master/admin)
  def update_rates
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'Solo master o admin pueden cambiar las tasas' }, status: :forbidden
    end

    limits = { 'tax_rate' => 100, 'interest_rate' => 100, 'waiver_rate' => 100,
               'mora_rate' => 500, 'cat_rate' => 1000, 'processing_fee' => 10_000 }
    defaults = { 'tax_rate' => 0, 'interest_rate' => 25, 'waiver_rate' => 0,
                 'mora_rate' => 0, 'cat_rate' => 0, 'processing_fee' => 0 }
    changes = []
    limits.each_key do |k|
      next unless params.key?(k)
      v = params[k].to_f
      return render(json: { error: "Valor inválido para #{k} (0 a #{limits[k]})" }, status: :unprocessable_entity) if v.negative? || v > limits[k]
      old = AppSetting.rate(k, defaults[k])
      new_v = v.round(4)
      changes << "#{k}: #{format('%g', old)} → #{format('%g', new_v)}" if old != new_v
      AppSetting.set(k, new_v.to_s)
    end
    if changes.any?
      AuditLog.record!(actor: @current_user, action: 'rates_updated',
                       label: 'Tasas e impuestos', details: changes.join(' · '))
    end
    rates
  end

  # GET /api/settings/rainforest
  # Devuelve si hay API key configurada (nunca el valor en claro).
  def rainforest
    key = AppSetting.get('rainforest_api_key')
    render json: { configured: key.present?, masked: (key.present? ? mask(key) : nil) }, status: :ok
  end

  # PUT /api/settings/rainforest  { api_key: '...' }
  def update_rainforest
    val = params[:api_key].to_s.strip
    return render json: { error: 'La API key es requerida.' }, status: :unprocessable_entity if val.blank?

    AppSetting.set('rainforest_api_key', val)
    render json: { configured: true, masked: mask(val) }, status: :ok
  end

  # POST /api/settings/rainforest/test  (consume 1 crédito de Rainforest)
  def test_rainforest
    result = RainforestImportService.new.test_connection
    render json: result, status: :ok
  end

  # GET /api/settings/contract
  # Plantilla del contrato de venta a crédito (personalizada de la BD, o la original del repo).
  def contract_template
    rec = AppSetting.find_by(key: CONTRACT_KEY)
    content = rec&.value.presence || default_contract_template
    render json: { content: content, custom: rec.present?, updated_at: rec&.updated_at }, status: :ok
  end

  # PUT /api/settings/contract  { content: '...' }  (solo master/admin)
  # PUT /api/settings/contract  { reset: true }     -> vuelve a la plantilla original
  def update_contract_template
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'Solo master o admin pueden editar el contrato' }, status: :forbidden
    end

    if ActiveModel::Type::Boolean.new.cast(params[:reset])
      AppSetting.find_by(key: CONTRACT_KEY)&.destroy
      AuditLog.record!(actor: @current_user, action: 'template_reset',
                       label: 'Control de documentos legales',
                       details: 'Restauró la plantilla original del contrato')
      return render json: { content: default_contract_template, custom: false, updated_at: nil }, status: :ok
    end

    val = params[:content].to_s
    return render json: { error: 'El contrato no puede quedar vacío.' }, status: :unprocessable_entity if val.strip.blank?

    rec = AppSetting.set(CONTRACT_KEY, val)
    AuditLog.record!(actor: @current_user, action: 'template_updated',
                     label: 'Control de documentos legales',
                     details: "Guardó la plantilla del contrato (#{val.length} caracteres)")
    render json: { ok: true, custom: true, updated_at: rec.updated_at }, status: :ok
  end

  private

  def default_contract_template
    path = Rails.root.join('db', 'templates', 'contract_template.txt')
    File.exist?(path) ? File.read(path) : ''
  end

  def mask(key)
    key.length > 8 ? "#{key[0, 4]}••••#{key[-4, 4]}" : '••••'
  end
end
