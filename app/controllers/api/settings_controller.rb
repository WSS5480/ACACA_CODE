class Api::SettingsController < ApplicationController
  include TokenAuthenticatable

  CONTRACT_KEY = 'contract_template'

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
      return render json: { content: default_contract_template, custom: false, updated_at: nil }, status: :ok
    end

    val = params[:content].to_s
    return render json: { error: 'El contrato no puede quedar vacío.' }, status: :unprocessable_entity if val.strip.blank?

    rec = AppSetting.set(CONTRACT_KEY, val)
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
