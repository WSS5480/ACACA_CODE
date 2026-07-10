class UserMailer < ApplicationMailer
  include LogoAttachable

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.user_mailer.send_welcome.subject
  #
  def send_welcome
    @user = params[:user]
    @pwrd = params[:pwrd]
    @login_url = frontend_base_url

    mail to: @user.email, subject: "Bienvenid@ a Acasa"
  end

  def send_client_number
    @user = params[:user]

    mail to: @user.email, subject: "Tu número de cliente Acasa"
  end

  def send_client_welcome
    @user = params[:user]
    raw_token = params[:confirmation_token]
    # Enlace al frontend: la página /confirmar-cuenta recibe el token y llama al API para confirmar.
    @confirmation_url = if raw_token.present?
      base = frontend_base_url
      "#{base}/confirmar-cuenta?confirmation_token=#{ERB::Util.url_encode(raw_token)}"
    end

    mail to: @user.email, subject: "¡Bienvenid@ a Acasa!"
  end

  # Notificación de nueva orden a la lista NOTIFICATE_TO (variable de entorno)
  def send_new_order_notification
    @order = params[:order]
    addresses = ["edcantu@hotmail.com", "diego@lagom.agency", "ruben@lagom.agency"] #ENV.fetch('NOTIFICATE_TO', '').split(',').map(&:strip).reject(&:blank?)
    return if addresses.empty?

    mail to: addresses, subject: "Nueva orden ##{@order.id} - Acasa"
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
