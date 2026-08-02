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
