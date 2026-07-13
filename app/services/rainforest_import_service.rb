require 'net/http'
require 'json'

# Cliente de Rainforest API para BUSCAR e IMPORTAR productos bajo demanda
# desde el admin de Ácasa. Importación ADITIVA (no desactiva el resto).
#
# Flujo: busca por palabra clave (1 crédito) y, para cada candidato, pide el
# DETALLE del producto (1 crédito c/u). El detalle trae las fotos reales
# (hasta 7) y el buybox con la información de vendedor/entrega, con lo que se
# aplican con certeza los filtros "vendido por Amazon" y "entregado por Amazon".
#
# La API key se lee de AppSetting ('rainforest_api_key'), respaldo ENV.
class RainforestImportService
  API_URL = 'https://api.rainforestapi.com/request'.freeze
  MAX_IMAGES = 7

  def initialize(api_key: nil)
    @api_key = api_key.presence || AppSetting.get('rainforest_api_key') || ENV['RAINFOREST_API_KEY']
  end

  def configured?
    @api_key.present?
  end

  # Prueba de conexión (consume 1 crédito).
  def test_connection
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?

    data = fetch(type: 'search', amazon_domain: 'amazon.com.mx', search_term: 'refrigerador')
    if data[:ok]
      { ok: true, message: "Conexión correcta (#{(data[:body]['search_results'] || []).size} resultados de prueba)." }
    else
      { ok: false, error: data[:error] }
    end
  end

  def search_and_import(search_term:, amazon_domain: 'amazon.com', sold_only: true, delivered_only: true, limit: 10)
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?
    return { ok: false, error: 'Escribe qué buscar.' } if search_term.blank?

    search = fetch(type: 'search', amazon_domain: amazon_domain, search_term: search_term)
    return { ok: false, error: search[:error] } unless search[:ok]

    asins = (search[:body]['search_results'] || []).map { |r| r['asin'] }.compact.uniq.first(limit)
    passing = []
    skipped = 0

    asins.each do |asin|
      detail = fetch(type: 'product', amazon_domain: amazon_domain, asin: asin)
      next unless detail[:ok]

      product_data = detail[:body]['product'] || {}
      next if product_data['asin'].blank?
      product_data['keywords'] ||= search_term

      fulfillment = (product_data['buybox_winner'] || {})['fulfillment'] || {}
      if (sold_only && !sold_by_amazon?(fulfillment)) || (delivered_only && !delivered_by_amazon?(fulfillment))
        skipped += 1
        next
      end

      passing << { 'success' => true, 'id' => product_data['asin'], 'result' => { 'product' => product_data } }
    end

    # Reutiliza el pipeline probado: convierte MXN->USD, baja hasta 7 fotos,
    # procesa categorías y calcula el pago semanal. Aditivo (no desactiva).
    # Importa como BORRADOR (inactive): no aparece en la tienda hasta publicar la categoría.
    ManageJson::ProcessProductsJob.new.perform(passing, false, 'inactive') if passing.any?

    { ok: true, checked: asins.size, imported: passing.size, skipped: skipped }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  private

  # Amazon es el VENDEDOR (no un tercero).
  def sold_by_amazon?(fulfillment)
    return true if truthy?(fulfillment['is_sold_by_amazon'])

    name = (fulfillment.dig('sold_by', 'name') || fulfillment['sold_by'] || fulfillment['third_party_seller_name']).to_s.downcase
    name.include?('amazon')
  end

  # Amazon EMBARCA/ENTREGA (Prime / fulfilled by Amazon).
  def delivered_by_amazon?(fulfillment)
    return true if truthy?(fulfillment['is_prime']) || truthy?(fulfillment['is_fulfilled_by_amazon'])

    name = (fulfillment.dig('ships_from', 'name') || fulfillment['ships_from']).to_s.downcase
    name.include?('amazon')
  end

  def truthy?(value)
    value == true || value.to_s.strip.downcase == 'true'
  end

  def fetch(params)
    uri = URI(API_URL)
    uri.query = URI.encode_www_form(params.merge(api_key: @api_key))

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
      http.get(uri.request_uri)
    end

    body = (JSON.parse(res.body) rescue {})
    if res.is_a?(Net::HTTPSuccess) && body.dig('request_info', 'success') != false
      { ok: true, body: body }
    else
      { ok: false, error: body.dig('request_info', 'message') || body['message'] || "Rainforest respondió #{res.code}" }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end
end
