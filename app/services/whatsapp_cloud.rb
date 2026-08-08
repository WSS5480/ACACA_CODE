# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# Envia mensajes por WhatsApp usando la Cloud API de Meta (Graph API).
# Variables de entorno:
#   WHATSAPP_TOKEN            -> token de acceso (System User token permanente en produccion)
#   WHATSAPP_PHONE_NUMBER_ID  -> ID del numero de WhatsApp Business
#   WHATSAPP_API_VERSION      -> opcional, por defecto 'v23.0'
#   VERIFY_DEFAULT_COUNTRY_CODE -> opcional, por defecto '1' (para numeros sin codigo de pais)
class WhatsappCloud
  class NotConfigured < StandardError; end
  class DeliveryError < StandardError; end

  GRAPH_HOST = 'graph.facebook.com'

  def self.configured?
    ENV['WHATSAPP_TOKEN'].present? && ENV['WHATSAPP_PHONE_NUMBER_ID'].present?
  end

  # Normaliza a digitos con codigo de pais (sin '+'), formato que espera Meta.
  def self.normalize_phone(raw, country_code: ENV.fetch('VERIFY_DEFAULT_COUNTRY_CODE', '1'))
    s = raw.to_s.strip
    return nil if s.blank?
    if s.start_with?('+')
      s.gsub(/[^0-9]/, '')
    else
      digits = s.gsub(/[^0-9]/, '')
      return nil if digits.blank?
      digits.length >= 11 ? digits : "#{country_code}#{digits}"
    end
  end

  def initialize
    raise NotConfigured, 'WhatsApp Cloud API no esta configurado' unless self.class.configured?
    @token = ENV['WHATSAPP_TOKEN']
    @phone_number_id = ENV['WHATSAPP_PHONE_NUMBER_ID']
    @version = ENV['WHATSAPP_API_VERSION'].presence || 'v23.0'
  end

  # Envia un mensaje de texto simple (gratis dentro de la ventana de 24h de servicio).
  def send_text(phone, body)
    to = self.class.normalize_phone(phone)
    raise DeliveryError, 'Numero de telefono invalido' if to.blank?
    post_message(messaging_product: 'whatsapp', recipient_type: 'individual', to: to, type: 'text', text: { body: body.to_s })
  end

  # Envía una PLANTILLA aprobada. Es la ÚNICA forma de iniciar conversación con
  # alguien que no nos ha escrito en las últimas 24 horas (fuera de esa ventana,
  # Meta acepta el texto libre y lo DESCARTA sin avisar).
  # params = valores de {{1}}, {{2}}... del cuerpo, en orden.
  def send_template(phone, name:, lang: 'es_MX', params: [])
    to = self.class.normalize_phone(phone)
    raise DeliveryError, 'Numero de telefono invalido' if to.blank?
    raise DeliveryError, 'Falta el nombre de la plantilla' if name.to_s.strip.blank?

    tpl = { name: name.to_s.strip, language: { code: lang.presence || 'es_MX' } }
    vals = Array(params).map(&:to_s).reject(&:blank?)
    tpl[:components] = [{ type: 'body', parameters: vals.map { |v| { type: 'text', text: v } } }] if vals.any?
    post_message(messaging_product: 'whatsapp', recipient_type: 'individual', to: to, type: 'template', template: tpl)
  end

  # ¿El error de Meta significa "fuera de la ventana de 24 horas"? (hay que usar plantilla)
  def self.window_error?(msg)
    m = msg.to_s
    m.include?('131047') || m =~ /re-?engagement|24 hours|outside the allowed window/i ? true : false
  end

  # Identificador de la cuenta de WhatsApp Business (para listar plantillas).
  def waba_id
    return @waba_id if defined?(@waba_id) && @waba_id
    @waba_id = ENV['WHATSAPP_WABA_ID'].presence
    @waba_id ||= begin
      r = get_json("https://#{GRAPH_HOST}/#{@version}/#{@phone_number_id}?fields=whatsapp_business_account")
      r.dig('whatsapp_business_account', 'id')
    rescue StandardError
      nil
    end
  end

  # Plantillas APROBADAS de la cuenta: [{name, language, body, params}]
  def templates
    id = waba_id
    return [] if id.blank?

    r = get_json("https://#{GRAPH_HOST}/#{@version}/#{id}/message_templates?limit=100&fields=name,status,language,components")
    (r['data'] || []).select { |t| t['status'].to_s.upcase == 'APPROVED' }.map do |t|
      body = (t['components'] || []).find { |c| c['type'].to_s.upcase == 'BODY' }
      text = body && body['text'].to_s
      { 'name' => t['name'], 'language' => t['language'], 'body' => text,
        'params' => text.to_s.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).max.to_i }
    end
  rescue StandardError => e
    Rails.logger.error "[WhatsappCloud] templates: #{e.message}"
    []
  end

  # Descarga un medio (imagen/documento) recibido: devuelve [binario, mime_type, filename] o nil.
  def download_media(media_id)
    return nil if media_id.blank?
    meta = get_json("https://#{GRAPH_HOST}/#{@version}/#{media_id}")
    url = meta['url']
    mime = meta['mime_type'].to_s
    return nil if url.blank?

    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{@token}"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) { |http| http.request(req) }
    return nil unless res.is_a?(Net::HTTPSuccess)

    ext = { 'image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp', 'application/pdf' => 'pdf' }[mime] || 'bin'
    [res.body, mime.presence || 'application/octet-stream', "wa_#{media_id}.#{ext}"]
  rescue StandardError => e
    Rails.logger.error "[WhatsappCloud] download_media #{media_id}: #{e.message}"
    nil
  end

  private

  def get_json(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{@token}"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(req) }
    safe_json(res.body)
  end

  def post_message(payload)
    uri = URI("https://#{GRAPH_HOST}/#{@version}/#{@phone_number_id}/messages")
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{@token}"
    req['Content-Type'] = 'application/json'
    req.body = payload.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
      http.request(req)
    end

    body = safe_json(res.body)
    unless res.is_a?(Net::HTTPSuccess)
      msg = body.dig('error', 'message') || res.message
      Rails.logger.error "[WhatsappCloud] send failed (#{res.code}): #{msg}"
      raise DeliveryError, msg
    end
    body
  end

  def safe_json(str)
    JSON.parse(str.to_s)
  rescue JSON::ParserError
    {}
  end
end
