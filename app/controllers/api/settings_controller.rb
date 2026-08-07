class Api::SettingsController < ApplicationController
  include TokenAuthenticatable

  # La lectura de tasas es PÚBLICA: la tienda la usa para calcular precios y pagos.
  skip_before_action :authenticate_entity!, only: [:rates], raise: false

  CONTRACT_KEY = 'contract_template'
  PRIVACY_KEY = 'privacy_policy'

  # La lectura del aviso de privacidad es PÚBLICA (la página /privacidad del sitio la muestra).
  skip_before_action :authenticate_entity!, only: [:rates, :privacy], raise: false

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

  # PUT /api/settings/rates { tax_rate, interest_rate, waiver_rate... }
  # master/admin: el cambio queda PENDIENTE hasta reunir las firmas de
  # administradores requeridas (4, o todos si hay menos). sistema: aplica directo.
  def update_rates
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden cambiar las tasas' }, status: :forbidden
    end

    limits = { 'tax_rate' => 100, 'interest_rate' => 100, 'waiver_rate' => 100,
               'mora_rate' => 500, 'cat_rate' => 1000, 'processing_fee' => 10_000 }
    defaults = { 'tax_rate' => 0, 'interest_rate' => 25, 'waiver_rate' => 0,
                 'mora_rate' => 0, 'cat_rate' => 0, 'processing_fee' => 0 }
    proposed = {}
    changes = []
    limits.each_key do |k|
      next unless params.key?(k)
      v = params[k].to_f
      return render(json: { error: "Valor inválido para #{k} (0 a #{limits[k]})" }, status: :unprocessable_entity) if v.negative? || v > limits[k]
      old = AppSetting.rate(k, defaults[k])
      new_v = v.round(4)
      next if old == new_v
      proposed[k] = new_v
      changes << "#{k}: #{format('%g', old)} → #{format('%g', new_v)}"
    end
    return rates if proposed.empty? # nada cambió

    # Rol sistema (Admin de sistemas) aplica directo; también si aún no corre la migración.
    if role == 'sistema' || !approvals_ready?
      proposed.each { |k, v| AppSetting.set(k, v.to_s) }
      AuditLog.record!(actor: @current_user, action: 'rates_updated',
                       label: 'Tasas e impuestos', details: changes.join(' · '))
      return rates
    end

    cr = ChangeRequest.propose!(kind: 'rates', payload: proposed,
                                summary: changes.join(' · '), proposer: @current_user)
    return rates if cr.status == 'applied' # equipo chico: tu firma bastó

    render json: { pending: true, change_request: cr.as_api,
                   message: "Cambio propuesto: requiere #{cr.required_signatures} firmas de administradores (la tuya ya cuenta). Se avisó por correo a los demás." },
           status: :accepted
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

  # PUT /api/settings/contract  { content: '...' }
  # PUT /api/settings/contract  { reset: true }     -> vuelve a la plantilla original
  # master/admin: queda PENDIENTE hasta reunir las firmas. sistema: aplica directo.
  def update_contract_template
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden editar el contrato' }, status: :forbidden
    end

    direct = role == 'sistema' || !approvals_ready?

    if ActiveModel::Type::Boolean.new.cast(params[:reset])
      if direct
        AppSetting.find_by(key: CONTRACT_KEY)&.destroy
        AuditLog.record!(actor: @current_user, action: 'template_reset',
                         label: 'Control de documentos legales',
                         details: 'Restauró la plantilla original del contrato')
        return render json: { content: default_contract_template, custom: false, updated_at: nil }, status: :ok
      end
      cr = ChangeRequest.propose!(kind: 'contract_template', payload: { 'reset' => true },
                                  summary: 'Restaurar la plantilla ORIGINAL del contrato',
                                  proposer: @current_user)
      return render(json: { content: default_contract_template, custom: false, updated_at: nil }, status: :ok) if cr.status == 'applied'

      return render json: { pending: true, change_request: cr.as_api,
                            message: "Restauración propuesta: requiere #{cr.required_signatures} firmas de administradores (la tuya ya cuenta)." },
                    status: :accepted
    end

    val = params[:content].to_s
    return render json: { error: 'El contrato no puede quedar vacío.' }, status: :unprocessable_entity if val.strip.blank?

    if direct
      rec = AppSetting.set(CONTRACT_KEY, val)
      AuditLog.record!(actor: @current_user, action: 'template_updated',
                       label: 'Control de documentos legales',
                       details: "Guardó la plantilla del contrato (#{val.length} caracteres)")
      return render json: { ok: true, custom: true, updated_at: rec.updated_at }, status: :ok
    end

    cr = ChangeRequest.propose!(kind: 'contract_template', payload: { 'content' => val },
                                summary: "Editó la plantilla del contrato (#{val.length} caracteres)",
                                proposer: @current_user)
    return render(json: { ok: true, custom: true, updated_at: Time.current }, status: :ok) if cr.status == 'applied'

    render json: { pending: true, change_request: cr.as_api,
                   message: "Cambio propuesto: requiere #{cr.required_signatures} firmas de administradores (la tuya ya cuenta). La plantilla actual sigue vigente mientras tanto." },
           status: :accepted
  end

  # GET /api/settings/privacy  (público)
  # Aviso de privacidad vigente: el editado de la BD, o el original del repo.
  def privacy
    rec = AppSetting.find_by(key: PRIVACY_KEY)
    content = rec&.value.presence || default_privacy_policy
    render json: { content: content, custom: rec.present?, updated_at: rec&.updated_at }, status: :ok
  end

  # PUT /api/settings/privacy  { content } | { reset: true }
  # Documento LEGAL: mismas reglas que el contrato — master/admin proponen y se
  # requieren las firmas de administradores; el rol sistema aplica directo.
  def update_privacy
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden editar el aviso de privacidad' }, status: :forbidden
    end

    direct = role == 'sistema' || !approvals_ready?

    if ActiveModel::Type::Boolean.new.cast(params[:reset])
      if direct
        AppSetting.find_by(key: PRIVACY_KEY)&.destroy
        AuditLog.record!(actor: @current_user, action: 'template_reset',
                         label: 'Aviso de privacidad', details: 'Restauró el aviso de privacidad original')
        return render json: { content: default_privacy_policy, custom: false, updated_at: nil }, status: :ok
      end
      cr = ChangeRequest.propose!(kind: 'privacy_policy', payload: { 'reset' => true },
                                  summary: 'Restaurar el aviso de privacidad ORIGINAL', proposer: @current_user)
      return render(json: { content: default_privacy_policy, custom: false, updated_at: nil }, status: :ok) if cr.status == 'applied'

      return render json: { pending: true, change_request: cr.as_api,
                            message: "Restauración propuesta: requiere #{cr.required_signatures} firmas de administradores." }, status: :accepted
    end

    val = params[:content].to_s
    return render json: { error: 'El aviso no puede quedar vacío.' }, status: :unprocessable_entity if val.strip.blank?

    if direct
      rec = AppSetting.set(PRIVACY_KEY, val)
      AuditLog.record!(actor: @current_user, action: 'template_updated',
                       label: 'Aviso de privacidad', details: "Guardó el aviso de privacidad (#{val.length} caracteres)")
      return render json: { ok: true, custom: true, updated_at: rec.updated_at }, status: :ok
    end

    cr = ChangeRequest.propose!(kind: 'privacy_policy', payload: { 'content' => val },
                                summary: "Editó el aviso de privacidad (#{val.length} caracteres)", proposer: @current_user)
    return render(json: { ok: true, custom: true, updated_at: Time.current }, status: :ok) if cr.status == 'applied'

    render json: { pending: true, change_request: cr.as_api,
                   message: "Cambio propuesto: requiere #{cr.required_signatures} firmas de administradores. El aviso actual sigue publicado mientras tanto." },
           status: :accepted
  end

  private

  def default_privacy_policy
    path = Rails.root.join('db', 'templates', 'privacy_policy.txt')
    File.exist?(path) ? File.read(path) : ''
  end

  # ¿Ya existe la tabla de aprobaciones? (si no, se aplica directo para no bloquear)
  def approvals_ready?
    ChangeRequest.table_exists?
  rescue StandardError
    false
  end

  def default_contract_template
    path = Rails.root.join('db', 'templates', 'contract_template.txt')
    File.exist?(path) ? File.read(path) : ''
  end

  def mask(key)
    key.length > 8 ? "#{key[0, 4]}••••#{key[-4, 4]}" : '••••'
  end
end
