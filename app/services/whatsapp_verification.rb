# frozen_string_literal: true

# Procesa un mensaje entrante de WhatsApp para activar (verificar) una cuenta.
# Match: 1) token incrustado en el texto  2) numero de telefono del remitente.
class WhatsappVerification
  def self.process_incoming(from:, body:)
    user = match_user(from: from, body: body)
    return nil if user.nil?
    return user if user.confirmed?

    user.update_column(:confirmed_at, Time.current)
    send_confirmation(user, from)
    user
  end

  def self.match_user(from:, body:)
    # 1) por token (cadenas alfanumericas de 8 a 12 caracteres en el mensaje)
    body.to_s.scan(/[A-Za-z0-9]{8,12}/).each do |candidate|
      u = User.find_by(whatsapp_verify_token: candidate)
      return u if u
    end
    # 2) por numero de telefono (ultimos 10 digitos del remitente)
    digits = from.to_s.gsub(/[^0-9]/, '')
    return nil if digits.length < 10
    tail = digits[-10, 10]
    User.where("regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{tail}").order(created_at: :desc).first
  end

  def self.send_confirmation(user, to)
    return unless WhatsappCloud.configured?
    store = (ENV['FRONT_HOST'].presence || 'https://www.acasamx.com').chomp('/')
    body = "¡Verificado! Tu cuenta acasa ya está activa. Bienvenid@ #{user.name}. " \
           "Por aquí podrás dar seguimiento a tus pedidos.\n\n" \
           "🛒 Empieza a comprar para tu familia en México: #{store}"
    resp = WhatsappCloud.new.send_text(to, body)
    # ARCHIVAR la respuesta automática: sin esto no aparece en la bandeja de
    # WhatsApp del admin (la bandeja muestra lo guardado en nuestra base).
    m = WhatsappMessage.new(user: user, direction: 'out',
                            wa_phone: WhatsappCloud.normalize_phone(to), body: body)
    m.wa_message_id = resp.dig('messages', 0, 'id') if resp.is_a?(Hash)
    m.status = 'sent' if m.has_attribute?(:status)
    m.save!
  rescue StandardError => e
    Rails.logger.error "[WhatsappVerification] reply failed: #{e.message}"
  end
end
