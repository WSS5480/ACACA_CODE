require 'net/http'
require 'json'
begin
  require 'redis-client' # provisto por Sidekiq 7 (RedisClient). Caché opcional; si falta, seguimos sin caché.
rescue LoadError
  nil
end

# Cliente de Rainforest API para BUSCAR e IMPORTAR productos bajo demanda
# desde el admin de acasa. Importación ADITIVA (no desactiva el resto).
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
  DETAIL_CACHE_TTL = 6 * 3600 # 6 horas: verificar deja el detalle en caché para que descargar NO recobre crédito.

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
    import_asins(asins, amazon_domain, sold_only: sold_only, delivered_only: delivered_only, keywords: search_term)
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # VISTA PREVIA de una categoría / más vendidos (1 crédito): devuelve la lista de
  # productos (asin, título, foto, precio) SIN importar, para que el admin elija.
  def category_preview(category_id:, amazon_domain: 'amazon.com.mx', limit: 50)
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?
    return { ok: false, error: 'Selecciona una categoría.' } if category_id.blank?

    list = fetch(type: 'bestsellers', category_id: category_id, amazon_domain: amazon_domain)
    return { ok: false, error: list[:error] } unless list[:ok]

    entries = list[:body]['bestsellers'] || list[:body]['category_results'] || list[:body]['search_results'] || []
    items = entries.first(limit).filter_map do |e|
      next if e['asin'].blank?
      price = e['price'] || {}
      {
        asin: e['asin'], title: e['title'], image: e['image'], link: e['link'],
        rating: e['rating'], price_value: price['value'],
        price_currency: price['currency'], price_raw: price['raw']
      }
    end
    { ok: true, count: items.size, items: items }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # VISTA PREVIA por PALABRA CLAVE con RANGO DE PRECIO (ej. "refrigerador", $5,000-$10,000).
  # Corre una búsqueda (type=search) y filtra por precio del lado del servidor usando el
  # price.value de cada resultado (los rangos de Amazon usan códigos de refinamiento
  # dinámicos, así que filtrar aquí es más confiable). NO importa; solo devuelve la lista
  # para que el admin elija, igual que category_preview. El precio está en la moneda del
  # dominio (MXN para amazon.com.mx).
  # CATEGORÍA DE AMAZON sin "más vendidos": el mismo type=search acepta
  # category_id (nodo real de Amazon), así que se puede buscar DENTRO de una
  # categoría con o sin palabra, con rango de precio y con el orden que se pida.
  # Rainforest exige search_term O category_id (al menos uno).
  SORT_BY = %w[bestseller_rankings most_recent price_low_to_high price_high_to_low featured average_review].freeze

  def search_preview(search_term:, amazon_domain: 'amazon.com.mx', min_price: nil, max_price: nil, limit: 50,
                     category_id: nil, sort_by: nil)
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?

    term = search_term.to_s.strip
    cat  = category_id.to_s.strip
    if term.blank? && cat.blank?
      return { ok: false, error: 'Escribe qué buscar (ej. refrigerador) o elige una categoría de Amazon.' }
    end

    min_p = min_price.present? ? min_price.to_f : nil
    max_p = max_price.present? ? max_price.to_f : nil

    # ALIAS vs NODO: Rainforest devuelve categorías de dos clases. Las numéricas
    # ('9687925011') son nodos REALES de Amazon y sirven para buscar dentro de la
    # categoría; las que no lo son ('bestsellers_electronics') son alias del
    # endpoint de más vendidos y NO se pueden buscar. Para que elegir cualquier
    # categoría siempre funcione:
    #   alias + sin palabra  -> su lista de más vendidos, con el rango de precio aplicado
    #   alias + con palabra  -> se busca la palabra (se avisa que la categoría no aplica)
    if cat.present? && !cat.match?(/\A\d+\z/)
      if term.blank?
        res = category_preview(category_id: cat, amazon_domain: amazon_domain, limit: 200)
        return res unless res[:ok]

        items = res[:items]
        if min_p || max_p
          items = items.select do |i|
            v = i[:price_value]
            !v.nil? && (min_p.nil? || v >= min_p) && (max_p.nil? || v <= max_p)
          end
        end
        return { ok: true, count: [items.size, limit].min, items: items.first(limit), mode: 'bestsellers',
                 note: 'Esa categoría de Amazon solo permite su lista de más vendidos; se le aplicó tu rango de precio.' }
      end

      cat = ''
      note_cat = 'La categoría elegida no se puede combinar con una palabra; se buscó solo la palabra.'
    end

    # Relevancia (sin ordenar por precio) para que los resultados abarquen todo el
    # espectro de precios; traemos 2 páginas para tener suficientes candidatos tras
    # filtrar por rango. Ordenar por precio concentraría los resultados en un extremo
    # y dejaría vacías las bandas intermedias/altas.
    params = { type: 'search', amazon_domain: amazon_domain, max_page: 2 }
    params[:search_term] = term if term.present?
    if cat.present?
      params[:category_id] = cat
      # Navegar una categoría completa: fuera los patrocinados (son ruido y casi
      # nunca pertenecen a la categoría que se está revisando).
      params[:exclude_sponsored] = 'true' if term.blank?
    end
    params[:sort_by] = sort_by.to_s if SORT_BY.include?(sort_by.to_s)

    search = fetch(params)
    return { ok: false, error: search[:error] } unless search[:ok]

    entries = search[:body]['search_results'] || []
    items = entries.filter_map do |e|
      next if e['asin'].blank?
      price = e['price'] || {}
      value = price['value']
      # Filtro por rango de precio (si el resultado no trae precio, se descarta cuando hay filtro).
      if min_p || max_p
        next if value.nil?
        next if min_p && value < min_p
        next if max_p && value > max_p
      end
      {
        asin: e['asin'], title: e['title'], image: e['image'], link: e['link'],
        rating: e['rating'], price_value: value,
        price_currency: price['currency'], price_raw: price['raw']
      }
    end.uniq { |i| i[:asin] }.first(limit)

    out = { ok: true, count: items.size, items: items }
    out[:note] = note_cat if defined?(note_cat) && note_cat.present?
    out
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # PROMOCIONES (type=deals): las ofertas VIGENTES de Amazon, de todo el sitio o
  # de una categoría. A diferencia de la búsqueda, cada renglón trae el precio de
  # oferta, el precio de lista y el % de descuento, que es lo que se pinta en la
  # vista previa. El rango de precio se aplica aquí (sobre el precio de oferta)
  # para no depender del formato de price_range de Rainforest.
  def deals_preview(category_id: nil, amazon_domain: 'amazon.com.mx', min_price: nil, max_price: nil, limit: 50)
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?

    min_p = min_price.present? ? min_price.to_f : nil
    max_p = max_price.present? ? max_price.to_f : nil

    params = { type: 'deals', amazon_domain: amazon_domain, max_page: 2 }
    params[:category_id] = category_id.to_s.strip if category_id.present?

    res = fetch(params)
    return { ok: false, error: res[:error] } unless res[:ok]

    entries = res[:body]['deals_results'] || res[:body]['deals'] || []
    items = entries.filter_map do |e|
      next if e['asin'].blank?

      price = e['deal_price'] || e['current_price'] || e['price'] || {}
      list  = e['list_price'] || {}
      value = price['value']
      if min_p || max_p
        next if value.nil?
        next if min_p && value < min_p
        next if max_p && value > max_p
      end
      pct = e['percent_off']
      pct = ((1 - (value.to_f / list['value'].to_f)) * 100).round if pct.blank? && value.to_f.positive? && list['value'].to_f.positive?
      {
        asin: e['asin'], title: e['title'], image: e['image'], link: e['link'],
        rating: e['rating'], price_value: value,
        price_currency: price['currency'], price_raw: money_raw(price),
        list_price_value: list['value'], list_price_raw: money_raw(list),
        percent_off: (pct.to_i.positive? ? pct.to_i : nil),
        deal_badge: (e['deal_badge'].presence || e['deal_type'].presence),
        is_lightning: e['is_lightning_deal'] == true
      }
    end.uniq { |i| i[:asin] }.first(limit)

    { ok: true, count: items.size, items: items, mode: 'deals' }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # "$1,234.56" a partir del objeto de precio de Rainforest (deals no siempre trae raw).
  def money_raw(price)
    return nil if price.blank?
    return price['raw'] if price['raw'].present?
    return nil if price['value'].blank?

    "#{price['symbol'] || '$'}#{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', price['value']))}"
  end

  # Importa SOLO los ASINs elegidos (1 crédito c/u) como BORRADOR (inactive), con
  # detalle completo (fotos reales, buybox) usando el pipeline probado.
  def import_selected(asins:, amazon_domain: 'amazon.com.mx', sold_only: false, delivered_only: false, keywords: nil, promo: nil)
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?
    list = Array(asins).map { |a| a.to_s.strip }.reject(&:blank?).uniq
    return { ok: false, error: 'Selecciona al menos un producto.' } if list.blank?

    import_asins(list, amazon_domain, sold_only: sold_only, delivered_only: delivered_only,
                                      keywords: keywords.presence, promo: promo)
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # Rainforest publica VARIOS catálogos de categorías y cada modo del scraper
  # necesita EL SUYO:
  #   standard    -> árbol real de Amazon (el de la barra del sitio). Es el único
  #                  que sirve para buscar dentro de una categoría (type=search),
  #                  y el único que baja hasta Videojuegos > PlayStation 5.
  #   bestsellers -> el de las listas de ranking (type=bestsellers).
  #   deals       -> el de las ofertas vigentes (type=deals).
  # Mezclarlos da "categoría no válida" o cero resultados.
  CATEGORY_TYPES = %w[standard bestsellers deals].freeze

  # Categorías de Amazon para los desplegables del scraper. Sin parent_id devuelve
  # los departamentos raíz; con parent_id, los hijos de ese nodo (así se baja de
  # Videojuegos a PlayStation 5 y a lo que haya debajo). has_children dice si ese
  # nodo todavía tiene otro nivel; nil = Amazon no lo informó.
  def amazon_categories(amazon_domain: 'amazon.com.mx', parent_id: nil, type: 'standard')
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?

    kind = CATEGORY_TYPES.include?(type.to_s) ? type.to_s : 'standard'
    params = { type: kind, domain: amazon_domain }
    params[:parent_id] = parent_id if parent_id.present?
    res = fetch_categories(params)
    return { ok: false, error: res[:error] } unless res[:ok]

    cats = (res[:body]['categories'] || res[:body]['bestsellers'] || []).filter_map do |c|
      id = c['id'] || c['category_id']
      next if id.blank?
      { id: id, name: c['name'] || id,
        has_children: c['has_children'].nil? ? nil : !!c['has_children'],
        path: c['path'] }
    end
    padre = res[:body]['current_category'] || res[:body]['parent_category']
    { ok: true, type: kind, categories: cats,
      parent: padre.is_a?(Hash) ? { id: padre['id'], name: padre['name'], path: padre['path'] } : nil }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # Nombre anterior: seguía pidiendo SOLO el catálogo de más vendidos.
  def bestseller_categories(amazon_domain: 'amazon.com.mx', parent_id: nil)
    amazon_categories(amazon_domain: amazon_domain, parent_id: parent_id, type: 'bestsellers')
  end

  # Verifica vendedor/envío de una lista de ASINs SIN importar (1 crédito c/u).
  # Devuelve { ASIN => { sold:, delivered:, seller: } } para pintar la insignia
  # "Amazon" en la vista previa antes de descargar.
  def check_sellers(asins:, amazon_domain: 'amazon.com.mx')
    return { ok: false, error: 'No hay API key de Rainforest configurada.' } unless configured?
    list = Array(asins).map { |a| a.to_s.strip }.reject(&:blank?).uniq
    return { ok: true, results: {} } if list.blank?

    results = {}
    list.each do |asin|
      product_data = fetch_product_detail(asin, amazon_domain)
      if product_data.blank?
        results[asin] = { error: true }
        next
      end
      f = (product_data['buybox_winner'] || {})['fulfillment'] || {}
      results[asin] = {
        sold: sold_by_amazon?(f),
        delivered: delivered_by_amazon?(f),
        seller: f.dig('third_party_seller', 'name'),
        # FOTO: si el ASIN ya está en nuestro catálogo, comparar NUESTRA foto
        # principal contra la foto principal ACTUAL de Amazon (por el ID de
        # imagen de Amazon, estable ante cambios de tamaño). false = Amazon
        # cambió la foto del listado y la nuestra ya no coincide.
        photo_match: photo_matches_ours?(asin, product_data),
        # ¿Amazon publica la foto principal del ASIN? (para ASINs nuevos: al
        # descargar se baja PRIMERO, garantizando nuestra foto #1)
        main_image_available: product_data.dig('main_image', 'link').present?,
        amazon_main_image: product_data.dig('main_image', 'link')
      }
    end
    { ok: true, results: results }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  # ¿La foto principal que tenemos guardada coincide con la principal actual
  # del ASIN en Amazon? nil = no se puede saber (no está en catálogo, no tiene
  # fotos, o Amazon no mandó main_image). Compara el ID de imagen de Amazon
  # (el nombre base antes del primer punto), que no cambia con los tamaños.
  def photo_matches_ours?(asin, product_data)
    main_link = product_data.dig('main_image', 'link').to_s
    return nil if main_link.blank?
    local = Product.find_by(asin: asin)
    return nil unless local&.images&.attached?

    amazon_id = File.basename(URI.parse(main_link).path).to_s.split('.').first.to_s
    our_id    = local.images.first.filename.to_s.split('.').first.to_s
    return nil if amazon_id.blank? || our_id.blank?

    amazon_id == our_id
  rescue StandardError => e
    Rails.logger.warn("[rainforest] comparación de foto #{asin}: #{e.message}")
    nil
  end

  private

  # Cliente Redis (redis-client, el mismo que usa Sidekiq 7). Si no está disponible, sin caché.
  def rf_cache
    return @rf_cache if defined?(@rf_cache)
    @rf_cache = (defined?(RedisClient) ? RedisClient.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')) : nil)
  rescue StandardError
    @rf_cache = nil
  end

  # Obtiene el detalle del producto (type=product = 1 crédito) PERO con caché en Redis:
  # si ya se pidió (p. ej. al "Verificar vendedor"), lo reusa sin gastar otro crédito.
  # Devuelve el hash del producto o nil.
  def fetch_product_detail(asin, amazon_domain)
    key = "rf:product:#{amazon_domain}:#{asin}"
    begin
      raw = rf_cache&.call('GET', key)
      return JSON.parse(raw) if raw.present?
    rescue StandardError => e
      Rails.logger.warn("[rainforest] cache read falló (#{e.message}); sigo sin caché")
    end

    detail = fetch(type: 'product', amazon_domain: amazon_domain, asin: asin)
    return nil unless detail[:ok]
    product_data = detail[:body]['product']
    return nil if product_data.blank?

    begin
      rf_cache&.call('SET', key, product_data.to_json, 'EX', DETAIL_CACHE_TTL)
    rescue StandardError => e
      Rails.logger.warn("[rainforest] cache write falló (#{e.message})")
    end
    product_data
  end

  # Descarga el detalle de cada ASIN e importa como BORRADOR (inactive) usando el
  # pipeline probado (MXN->USD, hasta 7 fotos, categorías, pago semanal). Aditivo.
  def import_asins(asins, amazon_domain, sold_only: true, delivered_only: true, keywords: nil, promo: nil)
    passing = []
    skipped = 0

    asins.each do |asin|
      product_data = fetch_product_detail(asin, amazon_domain)
      next if product_data.blank?
      next if product_data['asin'].blank?
      product_data['keywords'] ||= keywords if keywords.present?

      fulfillment = (product_data['buybox_winner'] || {})['fulfillment'] || {}
      sold_ok = sold_by_amazon?(fulfillment)
      deliv_ok = delivered_by_amazon?(fulfillment)
      if (sold_only && !sold_ok) || (delivered_only && !deliv_ok)
        Rails.logger.info("[rainforest] skip #{asin}: sold_by_amazon=#{sold_ok} delivered_by_amazon=#{deliv_ok} type=#{fulfillment['type']} seller=#{fulfillment.dig('third_party_seller', 'name')}")
        skipped += 1
        next
      end

      passing << { 'success' => true, 'id' => product_data['asin'], 'result' => { 'product' => product_data } }
    end

    ManageJson::ProcessProductsJob.new.perform(passing, false, 'active') if passing.any?

    # PROMOCIÓN: se marca DESPUÉS de crear/actualizar el producto, con lo que
    # enseñaba la lista de ofertas de Amazon. Los artículos en promoción se van
    # a la vista 0 solos (Product#effective_view) sin perder su vista.
    promocionados = 0
    if promo.is_a?(Hash) && promo[:percent_off].to_f.positive? && passing.any?
      asins_ok = passing.map { |x| x['id'] }.compact
      Product.where(asin: asins_ok).find_each do |p|
        p.apply_promo!(list_price: promo[:list_price], percent_off: promo[:percent_off], badge: promo[:badge])
        promocionados += 1
      end
    end

    { ok: true, checked: asins.size, imported: passing.size, skipped: skipped, promos: promocionados }
  end

  # Amazon es el VENDEDOR (no un tercero). Campos reales de Rainforest:
  # is_sold_by_amazon / is_sold_by_third_party / third_party_seller / type ("1p"=Amazon).
  def sold_by_amazon?(fulfillment)
    return false if truthy?(fulfillment['is_sold_by_third_party'])
    return true  if truthy?(fulfillment['is_sold_by_amazon'])
    return true  if fulfillment['type'].to_s.downcase == '1p'
    return false if fulfillment['third_party_seller'].present?

    name = (fulfillment.dig('sold_by', 'name') || fulfillment['sold_by']).to_s.downcase
    name.include?('amazon')
  end

  # Amazon EMBARCA/ENTREGA (FBA). Campos reales: is_fulfilled_by_amazon / is_fulfilled_by_third_party.
  def delivered_by_amazon?(fulfillment)
    return false if truthy?(fulfillment['is_fulfilled_by_third_party'])
    return true  if truthy?(fulfillment['is_fulfilled_by_amazon'])

    name = (fulfillment.dig('ships_from', 'name') || fulfillment['ships_from']).to_s.downcase
    name.include?('amazon')
  end

  def truthy?(value)
    value == true || value.to_s.strip.downcase == 'true'
  end

  def fetch_categories(params)
    uri = URI('https://api.rainforestapi.com/categories')
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
