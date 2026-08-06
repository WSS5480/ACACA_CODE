class Api::UsersController < ApplicationController
  include TokenAuthenticatable
  include ClientOrTokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticaciones por defecto
  skip_before_action :authenticate_entity!
  skip_before_action :authenticate_client_or_user!
  # Nivel 2: Solo JWT para index, create, destroy
  before_action :authenticate_entity!, only: [:index, :create, :destroy, :set_credit, :send_password_setup, :full_info]
  # Nivel 3: Cliente o JWT para show, update, current_user
  before_action :authenticate_client_or_user!, only: [:show, :update, :current_user]
  # Otros callbacks
  before_action :set_user, only: [:show, :update, :destroy]
  before_action :authorize_client_own_profile, only: [:show, :update]

  # GET /api/users  (solo staff)
  def index
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end
    users = User.includes(:role)
    users = users.joins(:role).where(roles: { name: params[:role] }) if params[:role].present?
    users = apply_search_filter(users, columns: %w[name last_name email number])
    render_paginated(users, UserSerializer)
  end

  # GET /api/users/:id
  def show
    render json: UserSerializer.new(@user).serializable_hash, status: :ok
  end

  # POST /api/users  (alta de usuarios del equipo — solo master/admin)
  def create
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    role = params[:user] && params[:user][:role_id].present? ? Role.find_by(id: params[:user][:role_id]) : nil
    if role&.name == 'master' && @current_user&.role&.name != 'master'
      return render json: { error: 'Solo master puede crear usuarios master' }, status: :forbidden
    end

    @user = User.new(user_params)
    @user.role = role if role

    # Sin contraseña capturada: se genera una aleatoria y el usuario crea la suya
    # con el enlace que le llega por correo (mismo flujo que "olvidé mi contraseña").
    generated = @user.password.blank?
    if generated
      tmp = SecureRandom.hex(16)
      @user.password = tmp
      @user.password_confirmation = tmp
    end

    if @user.save
      # Asegurarse de que usuarios no-clientes (admin, etc.) se confirman al crearse
      @user.confirm if @user.role&.name != 'cliente'
      sent = generated ? send_password_setup_email(@user).first : nil
      payload = UserSerializer.new(@user).serializable_hash
      if generated && !sent
        payload[:warning] = "El usuario se creó, pero el correo NO se pudo enviar#{@user.email.blank? ? ' (sin email)' : ''}. Revisa la configuración SMTP en Render y reenvía el enlace desde la tabla."
      end
      render json: payload, status: :created
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/users/:id/send_password_setup  — envía enlace para crear/cambiar contraseña
  def send_password_setup
    unless %w[master admin].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end
    user = User.find(params[:id])
    if user.email.blank?
      return render json: { error: 'Este usuario no tiene email registrado.' }, status: :unprocessable_entity
    end
    ok, err = send_password_setup_email(user)
    if ok
      render json: { ok: true, sent_to: user.email }, status: :ok
    else
      render json: { error: "No se pudo ENVIAR el correo a #{user.email}. Detalle SMTP: #{err}" }, status: :unprocessable_entity
    end
  end

  # GET /api/users/:id/full_info  (solo staff)
  # Ficha completa del cliente: datos de cuenta, cuestionario (preguntas y respuestas),
  # direcciones, beneficiarios, referencias, comentarios de verificación y bitácora.
  def full_info
    unless %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(@current_user&.role&.name)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    user = User.includes(:role, :credit).find_by(id: params[:id])
    return render(json: { error: 'Cliente no encontrado' }, status: :not_found) unless user

    orders = user.orders.includes(:buyer, :guarantor, :referrals, :beneficiary).order(:created_at)

    render json: {
      user: {
        id: user.id, name: user.name, last_name: user.last_name, email: user.email,
        phone: user.phone, number: user.number, created_at: user.created_at,
        risk_version: (user.respond_to?(:risk_version) ? user.risk_version : nil),
        credit_limit: user.credit_limit, available_credit: user.available_credit,
        # Respuestas del registro (precalificación)
        housing_type: user.housing_type, months_usa: user.months_usa,
        months_address: user.months_address, months_job: user.months_job,
        estimated_income: user.estimated_income, delivery_country: user.delivery_country,
        shared_income: user.shared_income
      },
      beneficiaries: user.beneficiaries.map do |b|
        { id: b.id, name: b.name, last_name: b.last_name, phone: b.phone, email: b.email,
          address1: b.address1, address2: b.address2, zip_code: b.zip_code, state: b.state, city: b.city }
      end,
      orders: orders.map { |o| order_full_info(o) },
      contracts: user.contracts.order(:created_at).map { |c| contract_sign_info(c) },
      contact_logs: ContactLog.where(user_id: user.id).order(:created_at).last(300).map do |l|
        { id: l.id, order_id: l.order_id, person_type: l.person_type, person_name: l.person_name,
          phone: l.phone, body: l.body, author_name: l.author_name, created_at: l.created_at }
      end
    }, status: :ok
  end

  # PATCH/PUT /api/users/:id
  def update
    if params[:user] && params[:user][:role_id].present?
      unless %w[master admin].include?(@current_user&.role&.name)
        return render json: { error: 'Solo un administrador puede cambiar roles' }, status: :forbidden
      end
      new_role = Role.find_by(id: params[:user][:role_id])
      if (new_role&.name == 'master' || @user.role&.name == 'master') && @current_user&.role&.name != 'master'
        return render json: { error: 'Solo master puede asignar o modificar el rol master' }, status: :forbidden
      end
      @user.role = new_role if new_role
    end

    if @user.update(user_params)
      render json: UserSerializer.new(@user).serializable_hash, status: :ok
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/users/:id
  # Cliente: lo elimina el staff operativo (admin si tiene contratos entregados).
  # USUARIO DEL EQUIPO (revocar acceso): master/admin — requiere las firmas de
  # administradores (4, o todos si hay menos); el rol 'sistema' revoca directo.
  def destroy
    role = @current_user&.role&.name
    target_role = @user.role&.name

    return revoke_staff_access!(role, target_role) if target_role.present? && target_role != 'cliente'

    unless %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(role)
      return render json: { error: 'No autorizado' }, status: :forbidden
    end

    contracts = @user.respond_to?(:contracts) ? @user.contracts.to_a : []
    # Un contrato esta ENTREGADO si alguna de sus ordenes ya se entrego.
    delivered = contracts.select do |c|
      c.orders.any? { |o| o.respond_to?(:delivered_at) && o.delivered_at.present? }
    end

    # Con contratos entregados, borrar cliente+contratos exige credenciales de ADMIN.
    if delivered.any? && !%w[master admin].include?(role)
      return render json: {
        error: "Este cliente tiene #{delivered.size} contrato(s) ENTREGADO(s). Solo un administrador puede eliminarlo."
      }, status: :forbidden
    end

    client_name = [@user.name, @user.last_name].compact.join(' ').strip
    client_email = @user.email
    ActiveRecord::Base.transaction do
      # Contratos primero (cascada pagos/cuotas), luego SUS ordenes (cascada comprador/aval/referencias).
      contracts.each(&:destroy!)
      @user.orders.find_each(&:destroy!)
      @user.destroy!
    end
    AuditLog.record!(actor: @current_user, action: 'client_deleted', target: @user,
                     label: (client_name.present? ? client_name : client_email),
                     details: "Cliente eliminado (#{client_email}) con #{contracts.size} contrato(s)")
    head :no_content
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Revocar el acceso de un usuario del EQUIPO: propone el cambio y exige las
  # firmas de administradores; 'sistema' (Admin de sistemas) lo aplica directo.
  def revoke_staff_access!(role, target_role)
    unless %w[master admin sistema].include?(role)
      return render json: { error: 'Solo master, admin o sistema pueden revocar acceso del equipo.' }, status: :forbidden
    end
    if target_role == 'master' && role != 'master'
      return render json: { error: 'Solo un usuario master puede revocar a otro master.' }, status: :forbidden
    end
    if @user.id == @current_user.id
      return render json: { error: 'No puedes revocar tu propia cuenta.' }, status: :unprocessable_entity
    end

    label = [@user.name, @user.last_name].compact.join(' ').strip.presence || @user.email

    approvals = begin
      ChangeRequest.table_exists?
    rescue StandardError
      false
    end

    if role == 'sistema' || !approvals
      @user.destroy!
      AuditLog.record!(actor: @current_user, action: 'staff_deleted', target: @user,
                       label: label, details: "Acceso revocado (#{@user.email}, rol #{target_role})")
      return head :no_content
    end

    existing = ChangeRequest.pending.where(kind: 'staff_delete').detect { |c| c.target_user_id == @user.id }
    if existing
      return render json: { pending: true, change_request: existing.as_api,
                            message: 'Ya hay una revocación PENDIENTE para este usuario: falta que la firmen los demás administradores.' },
                    status: :accepted
    end

    cr = ChangeRequest.propose!(
      kind: 'staff_delete',
      payload: { 'user_id' => @user.id, 'email' => @user.email, 'role' => target_role },
      summary: "Revocar acceso de #{label} (#{@user.email}, rol #{target_role})",
      proposer: @current_user, exclude_id: @user.id
    )
    return head :no_content if cr.status == 'applied' # tu firma bastó (equipo chico)

    render json: { pending: true, change_request: cr.as_api,
                   message: "Revocación propuesta: requiere #{cr.required_signatures} firmas de administradores (la tuya ya cuenta). El usuario conserva su acceso hasta completar las firmas." },
           status: :accepted
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/users/client_register
  def client_register
    client_role = Role.find_by(name: 'cliente')

    unless client_role
      return render json: { error: 'El rol de cliente no está configurado' }, status: :unprocessable_entity
    end

    @user = User.new(user_params)
    @user.role = client_role
    @user.number = generate_client_number
    # SEGURIDAD: el cliente define su propia contraseña (login por email + contraseña).
    if @user.password.blank?
      return render json: { error: 'La contraseña es requerida' }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      @user.save!
      # Guardar la versión del motor de riesgo usada para evaluar a este cliente.
      @user.update_column(:risk_version, @user.risk_engine_version) if User.column_names.include?('risk_version')
      initial_credit = @user.calculate_initial_credit
      credit_attrs = { amount: initial_credit }
      credit_attrs[:credit_limit] = initial_credit if Credit.column_names.include?('credit_limit')
      @user.create_credit!(credit_attrs)
    end

    # Token de verificacion por WhatsApp (se incrusta en el enlace/QR que el cliente nos envia).
    # Defensivo: si algo falla aqui (p.ej. la columna aun no migro), NO debe impedir crear la cuenta.
    begin
      @user.ensure_whatsapp_verify_token!
    rescue StandardError => wa_token_error
      Rails.logger.error "No se pudo generar el token de WhatsApp: #{wa_token_error.message}"
    end

    # Correo de bienvenida (solo bienvenida).
    if @user.email.present?
      begin
        UserMailer.with(user: @user).send_client_welcome.deliver_now
      rescue StandardError => mail_error
        Rails.logger.error "Error enviando correo de bienvenida: #{mail_error.message}"
      end
    end

    # Sin WhatsApp configurado (sin numero de negocio) activamos la cuenta para no bloquear el acceso.
    unless ENV['WHATSAPP_BUSINESS_NUMBER'].present?
      @user.update_column(:confirmed_at, Time.current)
    end

    render json: UserSerializer.new(@user).serializable_hash, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  # GET /api/current_user
  def current_user
    render json: UserSerializer.new(@current_user).serializable_hash, status: :ok
  end

  # POST /api/users/:id/set_credit  { amount }
  # Herramienta de PRUEBAS (solo staff): fija la linea de credito (disponible = limite).
  def set_credit
    return render(json: { error: 'No autorizado' }, status: :forbidden) unless %w[master admin].include?(@current_user&.role&.name)

    user = User.find_by(id: params[:id])
    return render(json: { error: 'Usuario no encontrado' }, status: :not_found) unless user

    amt = params[:amount].to_f
    return render(json: { error: 'Monto invalido' }, status: :unprocessable_entity) if amt < 0

    cr = user.credit || user.build_credit(amount: 0)
    old_amt = cr.amount.to_f
    cr.amount = amt.round(2)
    cr.credit_limit = amt.round(2) if Credit.column_names.include?('credit_limit')
    cr.save!
    AuditLog.record!(actor: @current_user, action: 'credit_set', target: user,
                     label: [user.name, user.last_name].compact.join(' ').strip.presence || user.email,
                     details: "Línea de crédito: $#{format('%.2f', old_amt)} → $#{format('%.2f', cr.amount)}")
    render json: { ok: true, credit_amount: cr.amount, credit_limit: (cr.respond_to?(:credit_limit) ? cr.credit_limit : cr.amount) }, status: :ok
  end

  private

  # Toda la información de una orden para la ficha del cliente.
  def order_full_info(o)
    buy = o.buyer
    ben = o.beneficiary
    gua = o.respond_to?(:guarantor) ? o.guarantor : nil
    {
      id: o.id, product_title: o.product_title, product_asin: o.product_asin,
      status: o.status, created_at: o.created_at,
      weekly_payment: o.weekly_payment, credit_duration: o.credit_duration,
      downpayment: o.downpayment, used_credit: o.used_credit,
      contract_number: (o.respond_to?(:contract) ? o.contract&.contract_number : nil),
      admin_approved: (o.respond_to?(:admin_approved) ? o.admin_approved : nil),
      delivered_at: (o.respond_to?(:delivered_at) ? o.delivered_at : nil),
      verification: {
        beneficiary_verified: try_f(o, :beneficiary_verified), beneficiary_comment: try_f(o, :beneficiary_comment),
        buyer_verified: try_f(o, :buyer_verified), buyer_comment: try_f(o, :buyer_comment),
        references_verified: try_f(o, :references_verified), references_comment: try_f(o, :references_comment)
      },
      buyer: buy && {
        name: buy.name, last_name: buy.last_name, nationality: buy.nationality,
        state_residence: buy.state_residence,
        living_address1: buy.living_address1, living_address2: buy.living_address2,
        living_zip_code: buy.living_zip_code, living_state: buy.living_state, living_city: buy.living_city,
        housing_type: buy.housing_type, months_usa: buy.months_usa, months_address: buy.months_address,
        job: buy.job, weekly_income: buy.weekly_income,
        phone: buy.phone, phone_work: buy.phone_work, email: buy.email,
        relationship_with_beneficiary: buy.relationship_with_beneficiary,
        delivery_address1: buy.delivery_address1, delivery_address2: buy.delivery_address2,
        delivery_zip_code: buy.delivery_zip_code, delivery_state: buy.delivery_state,
        delivery_city: buy.delivery_city, phone_beneficiary: buy.phone_beneficiary,
        # Copias entregadas por el cliente (expediente)
        identification_url: attach_url(buy, :identification),
        proof_of_address_url: attach_url(buy, :proof_of_address),
        proof_of_income_url: attach_url(buy, :proof_of_income)
      },
      beneficiary: ben && {
        name: ben.name, last_name: ben.last_name, phone: ben.phone, email: ben.email,
        address1: ben.address1, address2: ben.address2, zip_code: ben.zip_code,
        state: ben.state, city: ben.city,
        relationship: (ben.respond_to?(:relationship) ? ben.relationship : nil)
      },
      guarantor: gua && {
        name: gua.name, last_name: gua.last_name, phone: gua.phone, email: gua.email,
        address1: gua.address1, address2: gua.address2, zip_code: gua.zip_code,
        state: gua.state, city: gua.city
      },
      referrals: o.referrals.map do |rf|
        { name: rf.name, last_name: rf.last_name, nationality: rf.nationality,
          phone: rf.phone, phone_work: rf.phone_work }
      end
    }
  end

  def try_f(rec, field)
    rec.respond_to?(field) ? rec.public_send(field) : nil
  end

  # URL de un documento adjunto (identificación, comprobantes) o nil.
  def attach_url(rec, name)
    att = rec.public_send(name)
    return nil unless att.respond_to?(:attached?) && att.attached?
    att.url(expires_in: 1.hour)
  rescue StandardError
    begin
      Rails.application.routes.url_helpers.rails_blob_url(rec.public_send(name))
    rescue StandardError
      nil
    end
  end

  # Contrato + estado de firma para la ficha del cliente.
  def contract_sign_info(c)
    sig_url = nil
    if c.respond_to?(:signature) && c.signature.attached?
      sig_url = begin
        c.signature.url(expires_in: 1.hour)
      rescue StandardError
        begin
          Rails.application.routes.url_helpers.rails_blob_url(c.signature)
        rescue StandardError
          nil
        end
      end
    end
    {
      id: c.id,
      contract_number: c.contract_number,
      order_ref: (c.respond_to?(:order_ref) ? c.order_ref : "PED-#{c.id}"),
      status: c.status, payment_status: c.payment_status,
      total_amount: c.total_amount, created_at: c.created_at,
      initial_paid: (c.respond_to?(:initial_paid?) ? c.initial_paid? : true),
      document_generated_at: try_f(c, :document_generated_at),
      document_sent_at: try_f(c, :document_sent_at),
      signed_at: try_f(c, :signed_at),
      signature_name: try_f(c, :signature_name),
      signature_url: sig_url
    }
  end

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Usuario no encontrado' }, status: :not_found
  end

  def authorize_client_own_profile
    # Un cliente solo accede a SU PROPIO perfil. Con login por token (JWT) se
    # compara el id del usuario autenticado; la comparación por encabezado
    # ClientNumber es del flujo LEGADO (ya sin usar) y bloqueaba a todos los
    # clientes con 403 al editar su perfil.
    return unless acting_as_client?
    return if @current_user && @user.id == @current_user.id
    return if request.headers['ClientNumber'].present? && @user.number == request.headers['ClientNumber']

    render json: { error: 'No autorizado para ver este perfil' }, status: :forbidden
  end

  # Genera token de restablecimiento y envía el correo.
  # Devuelve [true, nil] o [false, detalle-del-error-SMTP].
  def send_password_setup_email(user)
    return [false, 'el usuario no tiene email'] if user.email.blank?
    token = SecureRandom.hex(24)
    user.update_columns(reset_password_token: token, reset_password_sent_at: Time.current)
    UserMailer.with(user: user, token: token).send_password_reset.deliver_now
    [true, nil]
  rescue StandardError => e
    Rails.logger.error "No se pudo enviar el correo de contraseña a #{user.email}: #{e.class}: #{e.message}"
    [false, "#{e.class}: #{e.message.to_s.strip[0, 300]}"]
  end

  def user_params
    params.require(:user).permit(
      :email,
      :password,
      :password_confirmation,
      :name,
      :last_name,
      :phone,
      :housing_type,
      :months_usa,
      :months_address,
      :months_job,
      :estimated_income,
      :delivery_country,
      :shared_income
    )
  end

  def generate_client_number
    max_attempts = 100
    attempts = 0

    loop do
      attempts += 1
      number = rand(100000..999999).to_s

      return number unless User.exists?(number: number)

      if attempts >= max_attempts
        raise StandardError, "No se pudo generar un número de cliente único después de #{max_attempts} intentos"
      end
    end
  end
end

