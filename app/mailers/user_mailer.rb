class UserMailer < ApplicationMailer
  include LogoAttachable
  helper MailFormatHelper

  # Textos de los correos de ETAPA (después del pago inicial). %{num} = número
  # de pedido/contrato. Español primero y una línea en inglés al final.
  STAGE_COPY = {
    'datos_recibidos' => {
      subject: 'Recibimos tu información', title: 'Recibimos tu información',
      es: 'Ya tenemos tus datos de comprador y tus referencias para el pedido %{num}. Nuestro equipo los está verificando: no tienes que hacer nada más por ahora, te avisamos en cuanto termine.',
      step: 'Paso 4 de 6 · Verificamos tu información',
      en: 'We received your buyer details and references for order %{num}. Our team is verifying them now; nothing else is needed from you for the moment.'
    },
    'verificado' => {
      subject: 'Tu información fue verificada', title: 'Información verificada ✓',
      es: 'Verificamos tus datos y tus referencias del pedido %{num}. Solo falta la aprobación final de nuestro equipo.',
      step: 'Paso 5 de 6 · Aprobación final',
      en: 'Your details and references for order %{num} were verified. Only the final approval remains.'
    },
    'aprobado' => {
      subject: '¡Aprobación final!', title: '¡Tu compra fue aprobada! 🎉',
      es: 'Tu pedido %{num} recibió la aprobación final. En breve recibirás tu contrato para firmarlo desde tu celular o tu computadora (te llega por correo y por WhatsApp).',
      step: 'Siguiente · Firma de tu contrato',
      en: 'Order %{num} received final approval. You will shortly receive your contract to sign from your phone or computer (by email and WhatsApp).'
    },
    'firmado' => {
      subject: 'Contrato firmado', title: 'Contrato firmado ✓',
      es: 'Recibimos tu firma del contrato %{num}. Ya estamos preparando tu entrega en México; te avisamos en cuanto salga. Abajo está tu calendario de pagos.',
      step: 'Paso 6 de 6 · Entrega',
      en: 'We received your signature for contract %{num}. We are preparing your delivery in Mexico; your payment schedule is below.'
    },
    'entregado' => {
      subject: '¡Entregado!', title: '¡Tu pedido fue entregado! 🚚',
      es: 'Tu pedido %{num} ya fue entregado. Gracias por comprar con acasa. Abajo está tu calendario de pagos con lo pagado y lo que falta; cada pago te llegará con su recibo.',
      step: 'Tu contrato está activo',
      en: 'Order %{num} has been delivered. Thank you for shopping with acasa. Your payment schedule, with what is paid and what remains, is below.'
    }
  }.freeze

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.user_mailer.send_welcome.subject
  #
  def send_welcome
    @user = params[:user]
    @pwrd = params[:pwrd]
    @login_url = frontend_base_url

    mail to: @user.email, subject: "Bienvenid@ a acasa"
  end

  def send_client_number
    @user = params[:user]

    mail to: @user.email, subject: "Tu número de cliente acasa"
  end

  def send_client_welcome
    @user = params[:user]
    raw_token = params[:confirmation_token]
    # Enlace al frontend: la página /confirmar-cuenta recibe el token y llama al API para confirmar.
    @confirmation_url = if raw_token.present?
      base = frontend_base_url
      "#{base}/confirmar-cuenta?confirmation_token=#{ERB::Util.url_encode(raw_token)}"
    end
    # VERIFICACIÓN POR WHATSAPP (principal): botón wa.me con el código del
    # cliente ya escrito; al enviarnos ese mensaje, el webhook activa la cuenta
    # y además queda abierta su ventana de 24 h para conversar.
    @whatsapp_url = begin
      @user.ensure_whatsapp_verify_token! if @user.respond_to?(:ensure_whatsapp_verify_token!)
      @user.respond_to?(:whatsapp_verify_url) ? @user.whatsapp_verify_url : nil
    rescue StandardError
      nil
    end
    @store_url = frontend_base_url

    mail to: @user.email, subject: "¡Bienvenid@ a acasa!"
  end

  # Enlace para crear una nueva contraseña (bilingüe ES/EN — no guardamos
  # preferencia de idioma por cliente todavía, así el correo sirve para todos).
  def send_password_reset
    @user = params[:user]
    @reset_url = "#{frontend_base_url}/restablecer?token=#{ERB::Util.url_encode(params[:token])}"

    mail to: @user.email, subject: 'Restablece tu contraseña / Reset your password — acasa'
  end

  # Enlace para FIRMAR el contrato (respaldo/refuerzo del WhatsApp — bilingüe ES/EN).
  def send_contract_signing
    @user = params[:user]
    @contract = params[:contract]
    @sign_url = "#{frontend_base_url}/contratos/#{@contract.id}/firmar"

    mail to: @user.email, subject: "Firma tu contrato #{@contract.contract_number} / Sign your contract — acasa"
  end

  # Aviso a un administrador: hay un cambio sensible PENDIENTE DE FIRMA
  # (Tasas e impuestos, documentos legales o revocación de acceso del equipo).
  def send_change_approval
    @admin = params[:user]
    @change = params[:change]
    @kind_label = ChangeRequest::KINDS[@change.kind] || @change.kind
    host = ENV['API_HOST'].presence || 'acasa-web.onrender.com'
    @admin_url = "https://#{host.sub(%r{\Ahttps?://}, '').chomp('/')}/admin.html"

    mail to: @admin.email, subject: "Firma requerida: cambio en #{@kind_label} — acasa"
  end

  # Correo LIBRE del equipo a una persona (CRM, cobranza, seguimiento).
  # El texto lo escribe el asesor; queda registrado en la bitácora de la persona.
  def send_staff_message
    @to = params[:to]
    @name = params[:name]
    @body = params[:body]
    @from_name = params[:from_name]
    subject = params[:subject].presence || 'Mensaje de acasa'

    mail to: @to, subject: subject
  end

  # ALERTA al equipo: una cuenta NUEVA se registró con el teléfono de una cuenta
  # EXISTENTE ya verificada por WhatsApp (posible duplicado o suplantación).
  def send_duplicate_phone_alert
    @new_user = params[:new_user]
    @existing = params[:existing]
    addresses = ENV.fetch('NOTIFICATE_TO', '').split(',').map(&:strip).reject(&:blank?)
    addresses = ['clientes@acasamx.com'] if addresses.empty?

    mail to: addresses, subject: "⚠ Teléfono duplicado: registro nuevo usa el número de la cuenta ##{@existing&.number} — acasa"
  end

  # Notificación de nueva orden a la lista NOTIFICATE_TO (variable de entorno).
  # SIN direcciones de la agencia: sólo lo que esté configurado (o el buzón propio).
  def send_new_order_notification
    @order = params[:order]
    addresses = ENV.fetch('NOTIFICATE_TO', '').split(',').map(&:strip).reject(&:blank?)
    addresses = ['clientes@acasamx.com'] if addresses.empty?
    return if addresses.empty?

    mail to: addresses, subject: "Nueva orden ##{@order.id} - acasa"
  end

  # RECIBO por cada pago: el mismo recibo de la tienda (Recibos e impresión)
  # más el calendario de pagos con lo pagado y lo que falta.
  def send_payment_receipt
    @user = params[:user]
    @contract = params[:contract]
    @payment = params[:payment]
    @num = @contract.contract_number.presence || @contract.order_ref
    @client_name = [@user.name, @user.last_name].compact.join(' ').strip
    @r = @contract.receipt_data_for(@payment)
    @installments = @contract.contract_installments.order(:number).to_a
    @contract_url = "#{frontend_base_url}/contratos/#{@contract.id}"
    @is_initial = %w[enganche contado].include?(@r[:kind])
    @needs_datos = !@contract.datos_complete?
    @paid_off = @contract.paid_off?
    nxt = @contract.contract_installments.where.not(status: 'paid').order(:due_date).first
    @next_due = nxt&.due_date
    @next_amount = nxt ? (nxt.amount.to_f - nxt.paid_amount.to_f).round(2) : nil

    mail to: @user.email, subject: "Recibo de pago #{@r[:folio]} · #{@num} — acasa"
  end

  # AVISO de cada etapa después del pago inicial (una vez por etapa).
  def send_stage_update
    @user = params[:user]
    @contract = params[:contract]
    @stage = params[:stage].to_s
    @copy = STAGE_COPY.fetch(@stage)
    @num = @contract.contract_number.presence || @contract.order_ref
    @client_name = [@user.name, @user.last_name].compact.join(' ').strip
    @contract_url = "#{frontend_base_url}/contratos/#{@contract.id}"
    @show_schedule = %w[firmado entregado].include?(@stage)
    @installments = @show_schedule ? @contract.contract_installments.order(:number).to_a : []
    nxt = @contract.contract_installments.where.not(status: 'paid').order(:due_date).first
    @next_due = nxt&.due_date
    @next_amount = nxt ? (nxt.amount.to_f - nxt.paid_amount.to_f).round(2) : nil

    mail to: @user.email, subject: "#{@copy[:subject]} · #{@num} — acasa"
  end

  # El AUTOPAGO no pudo cobrar porque el banco del cliente exige que él
  # confirme el cargo (3-D Secure/SCA, común fuera de EE. UU.). Se le pide
  # entrar a Mis pagos y pagar desde ahí; el cargo es en dólares (USD).
  def send_payment_action_required
    @user = params[:user]
    @contract = params[:contract]
    @amount = params[:amount].to_f
    @num = @contract.contract_number.presence || @contract.order_ref
    @client_name = [@user.name, @user.last_name].compact.join(' ').strip
    @contract_url = "#{frontend_base_url}/contratos/#{@contract.id}"
    @pay_url = "#{frontend_base_url}/pagos"

    mail to: @user.email, subject: "Tu banco pide confirmar tu pago · #{@num} — acasa"
  end

  private

  # En producción: si api_consumer_host es una lista separada por comas (ej. "http://localhost:3000,https://www-acasa.vercel.app"), usa la primera URL que no sea de desarrollo.
  # En desarrollo/test: usa el valor tal cual (solo se quita la barra final).
  def frontend_base_url
    raw = Rails.configuration.x.api_consumer_host.to_s.sub(%r{/$}, '')
    return raw unless Rails.env.production?

    candidates = raw.split(',').map(&:strip).reject(&:blank?)
    chosen = candidates.find { |url| !development_url?(url) } || candidates.first || raw
    chosen.sub(%r{/$}, '')
  end

  def development_url?(url)
    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    host == 'localhost' || host == '127.0.0.1' || host.end_with?('.local')
  rescue URI::InvalidURIError
    false
  end
end
