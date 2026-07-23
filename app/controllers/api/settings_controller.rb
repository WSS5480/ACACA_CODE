class Api::SettingsController < ApplicationController
  include TokenAuthenticatable

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

  private

  def mask(key)
    key.length > 8 ? "#{key[0, 4]}••••#{key[-4, 4]}" : '••••'
  end
end
