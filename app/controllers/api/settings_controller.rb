class Api::SettingsController < ApplicationController
  include TokenAuthenticatable

  # La lectura de tasas es PÚBLICA: la tienda la usa para calcular precios y pagos.
  skip_before_action :authenticate_entity!, only: [:rates], raise: false

  CONTRACT_KEY = 'contract_template'
  PRIVACY_KEY = 'privacy_policy'

  # La lectura del aviso de privacidad es PÚBLICA (la página /privacidad del sitio la muestra).
  # La lectura de las preguntas de aprobación también: el REGISTRO (público) la
  # usa para mostrar/ocultar sus preguntas informativas según la lista maestra.
  skip_before_action :authenticate_entity!, only: [:rates, :privacy, :approval_questions], raise: false

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
      cash_factor: Product.default_cash_factor,
      pti_max: (Product.respond_to?(:pti_max) ? Product.pti_max : 0),
      pti_max_variable: (Product.respond_to?(:pti_max_variable) ? Product.pti_max_variable : 0),
      category_down_floors: (defined?(CategoryFloor) ? CategoryFloor.floors : {}),
      category_floor_base: (defined?(CategoryFloor) ? CategoryFloor::BASE_PCT : 10)
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
               'mora_rate' => 500, 'cat_rate' => 1000, 'processing_fee' => 10_000,
               'pti_max' => 100, 'pti_max_variable' => 100 }
    defaults = { 'tax_rate' => 0, 'interest_rate' => 25, 'waiver_rate' => 0,
                 'mora_rate' => 0, 'cat_rate' => 0, 'processing_fee' => 0,
                 'pti_max' => 0, 'pti_max_variable' => 0 }
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
      # La tasa cambia los pagos amortizados: refrescar el "Desde" guardado.
      Product.refresh_min_weekly! if proposed.key?('interest_rate')
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

  # PUT /api/settings/category_floors { floors: { "Electrónica" => 20, ... } }
  # Enganche mínimo por CATEGORÍA (%). Vacío o <=10 = piso base del 10%.
  def update_category_floors
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden cambiar los pisos' }, status: :forbidden
    end

    raw = params[:floors].respond_to?(:to_unsafe_h) ? params[:floors].to_unsafe_h : {}
    clean = {}
    CategoryFloor::DEPTS.keys.each do |d|
      v = raw[d].to_f
      next if v <= CategoryFloor::BASE_PCT # 10 o menos = piso base, no se guarda

      return render(json: { error: "Valor invalido para #{d} (entre 10 y 90)" }, status: :unprocessable_entity) if v > 90

      clean[d] = v.round(2)
    end
    AppSetting.set('category_down_floors', clean.to_json)
    AuditLog.record!(actor: @current_user, action: 'rates_updated',
                     label: 'Enganche mínimo por categoría',
                     details: clean.map { |k, v| "#{k}: #{format('%g', v)}%" }.join(' · ').presence || 'Todo al piso base (10%)')
    render json: { ok: true, floors: clean }, status: :ok
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

  QUESTIONS_KEY = 'approval_questions'
  # Preguntas ACTUALES del proceso (semilla editable): las de PRE-APROBACIÓN se
  # hacen al abrir la cuenta (alimentan el motor de riesgo) y las de APROBACIÓN
  # FINAL al completar la compra (expediente que verifica el equipo).
  DEFAULT_QUESTIONS = {
    'pre' => [
      '¿Tu vivienda es propia o rentada?',
      '¿Cuántos meses llevas viviendo en Estados Unidos?',
      '¿Cuántos meses llevas en tu domicilio actual?',
      '¿Cuántos meses llevas en tu empleo actual?',
      '¿Cuál es tu ingreso semanal estimado?',
      '¿A qué país se entregará tu compra?',
      '¿Compartes tu ingreso con alguien más?'
    ],
    'final' => [
      'Datos del comprador: nombre, nacionalidad y estado donde vive',
      'Domicilio completo en EE.UU. y tipo de vivienda (propia o rentada)',
      'Contacto de tu domicilio (casero o conocido) y su teléfono',
      'Empleo, teléfono del trabajo e ingreso semanal',
      'Identificación oficial, comprobante de domicilio y de ingresos',
      '2 referencias en México (nombre, teléfono y tel. de trabajo)',
      '2 referencias en Estados Unidos (nombre, teléfono y tel. de trabajo)',
      'Quien recibe en México: nombre, teléfono y dirección'
    ]
  }.freeze

  # GET /api/settings/approval_questions
  def approval_questions
    rec = AppSetting.find_by(key: QUESTIONS_KEY)
    data = begin
      JSON.parse(rec&.value.to_s)
    rescue StandardError
      nil
    end
    unless data.is_a?(Hash) && data['pre'].is_a?(Array)
      data = { 'pre' => DEFAULT_QUESTIONS['pre'].each_with_index.map { |t, i| { 'id' => i + 1, 'text' => t, 'active' => true } },
               'final' => DEFAULT_QUESTIONS['final'].each_with_index.map { |t, i| { 'id' => i + 101, 'text' => t, 'active' => true } } }
    end
    render json: { questions: data, updated_at: rec&.updated_at }, status: :ok
  end

  # PUT /api/settings/approval_questions { questions: { pre: [...], final: [...] } }
  def update_approval_questions
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden editar las preguntas' }, status: :forbidden
    end

    q = params[:questions]
    return render(json: { error: 'Formato inválido' }, status: :unprocessable_entity) unless q.respond_to?(:[])

    clean = {}
    %w[pre final].each do |k|
      list = Array(q[k]).map do |it|
        { 'id' => it[:id].to_i, 'text' => it[:text].to_s.strip[0, 300],
          'active' => ActiveModel::Type::Boolean.new.cast(it[:active]) }
      end.reject { |it| it['text'].blank? }
      return render(json: { error: "Máximo 40 preguntas por lista (#{k})" }, status: :unprocessable_entity) if list.size > 40

      nid = (list.map { |i| i['id'] }.max || 0) + 1
      list.each { |i| (i['id'] = nid; nid += 1) if i['id'] <= 0 }
      clean[k] = list
    end
    AppSetting.set(QUESTIONS_KEY, clean.to_json)
    AuditLog.record!(actor: @current_user, action: 'questions_updated',
                     label: 'Preguntas de aprobación',
                     details: "Pre: #{clean['pre'].size} · Final: #{clean['final'].size}")
    render json: { ok: true, questions: clean }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/settings/wa_responses — repositorio de respuestas automáticas de
  # WhatsApp (Configuración → Respuestas WhatsApp), con original y texto vigente.
  def wa_responses
    render json: { responses: WaAutoText.all,
                   alert_numbers: (defined?(WaAlert) ? AppSetting.get(WaAlert::SETTING_KEY).to_s : '') }, status: :ok
  end

  # PUT /api/settings/wa_responses { responses: { clave => texto } }
  # Texto vacío = volver al ORIGINAL de esa respuesta.
  def update_wa_responses
    role = @current_user&.role&.name
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden editar las respuestas' }, status: :forbidden
    end

    incoming = params[:responses].respond_to?(:to_unsafe_h) ? params[:responses].to_unsafe_h : params[:responses]
    return render(json: { error: 'Formato inválido' }, status: :unprocessable_entity) unless incoming.is_a?(Hash)

    clean = incoming.slice(*WaAutoText::DEFAULTS.keys)
                    .transform_values { |v| v.to_s.strip }
                    .reject { |k, v| v.blank? || v == WaAutoText::DEFAULTS.dig(k, :text) }
    WaAutoText.save!(clean)
    WaAlert.numbers = params[:alert_numbers].to_s if params.key?(:alert_numbers) && defined?(WaAlert)
    AuditLog.record!(actor: @current_user, action: 'wa_responses_updated',
                     details: "Respuestas personalizadas: #{clean.size} de #{WaAutoText::DEFAULTS.size}" \
                              "#{params.key?(:alert_numbers) ? " · Alertas internas: #{WaAlert.numbers.size} número(s)" : ''}")
    render json: { ok: true, responses: WaAutoText.all }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
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
