# frozen_string_literal: true

require 'net/http'
require 'uri'

# Revisión GRATUITA de un producto contra su página pública de Amazon
# (NO usa créditos de Rainforest):
#   - available:   ¿sigue publicado el listado?
#   - photo_match: ¿nuestra foto principal sigue siendo la principal del ASIN?
#                  (se compara el ID de imagen de Amazon, estable ante tamaños)
#
# La usan: el botón "Verificar en Amazon" del catálogo (admin) y la RONDA
# AUTOMÁTICA del catálogo (CatalogPatrol, cada tick).
class AmazonPageCheck
  UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'
  GONE_MARKERS = ['página no encontrada', 'pagina no encontrada', 'no está disponible', 'no esta disponible',
                  'currently unavailable', 'no disponible actualmente', 'dogs of amazon', 'perritos de amazon'].freeze

  def self.call(product)
    asin = product.asin.to_s.strip
    url = product.original_link.presence || (asin.present? ? "https://www.amazon.com.mx/dp/#{asin}" : nil)
    return { available: nil, code: 0, reason: 'sin link/asin', photo_match: nil } if url.blank?

    current = url
    3.times do
      uri = URI.parse(current)
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = UA
      req['Accept-Language'] = 'es-MX,es;q=0.9'
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 12) { |http| http.request(req) }

      case res
      when Net::HTTPNotFound
        return { available: false, code: 404, reason: '404 no encontrado', photo_match: nil }
      when Net::HTTPRedirection
        current = URI.join(current, res['location'].to_s).to_s
        next
      when Net::HTTPSuccess
        body = res.body.to_s
        low  = body.downcase
        gone = GONE_MARKERS.any? { |m| low.include?(m) }
        asin_present = asin.blank? || low.include?(asin.downcase)
        available = !gone && asin_present
        return {
          available: available,
          code: res.code.to_i,
          reason: (gone ? 'marcado no disponible' : (asin_present ? 'ok' : 'asin ausente en la página')),
          photo_match: (available ? photo_match_for(product, body) : nil)
        }
      else
        # 503/CAPTCHA/bloqueo => no se pudo determinar; no marcar en rojo.
        return { available: nil, code: res.code.to_i, reason: "respuesta #{res.code}", photo_match: nil }
      end
    end
    { available: nil, code: 0, reason: 'demasiadas redirecciones', photo_match: nil }
  rescue StandardError => e
    { available: nil, code: 0, reason: e.message, photo_match: nil }
  end

  # ID de la imagen principal en la página (imageBlock: "hiRes"/"large" o landingImage).
  # nil si no se puede extraer o si no tenemos fotos propias para comparar.
  def self.photo_match_for(product, body)
    return nil unless product.images.attached?

    amazon_id = extract_main_image_id(body)
    return nil if amazon_id.blank?

    our_id = product.images.first.filename.to_s.split('.').first.to_s
    return nil if our_id.blank?

    amazon_id == our_id
  rescue StandardError
    nil
  end

  def self.extract_main_image_id(body)
    # 1) Bloque de imágenes (JSON embebido): la primera "hiRes"/"large" es la principal.
    m = body.match(/"hiRes"\s*:\s*"https:[^"]*\/images\/I\/([A-Za-z0-9%+\-_]+)\./) ||
        body.match(/"large"\s*:\s*"https:[^"]*\/images\/I\/([A-Za-z0-9%+\-_]+)\./)
    return m[1] if m

    # 2) landingImage (img principal del DOM).
    m = body.match(/id="landingImage"[^>]{0,600}?\/images\/I\/([A-Za-z0-9%+\-_]+)\./m)
    return m[1] if m

    # 3) og:image (meta).
    m = body.match(/property="og:image"[^>]{0,300}?\/images\/I\/([A-Za-z0-9%+\-_]+)\./m)
    m ? m[1] : nil
  end
end
