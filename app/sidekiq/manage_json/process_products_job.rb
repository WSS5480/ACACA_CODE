class ManageJson::ProcessProductsJob
  include Sidekiq::Job

  require 'open-uri'
  require 'set'
  require 'zip'

  def perform(products_data)
    return if products_data.blank?

    # Detectar tipo de respuesta y obtener el array de productos
    products_array = extract_products_array(products_data)

    return if products_array.blank?

    if ExchangeRate.current_rate <= 0
      Rails.logger.error "❌ No se puede procesar productos: ExchangeRate.current_rate debe ser mayor a 0"
      return
    end

    Rails.logger.info "Procesando #{products_array.size} productos..."

    created_count = 0
    updated_count = 0
    errors = []
    asins_in_payload = Set.new

    products_array.each do |item|
      next unless item['success'] && item['result'].present?

      product_data = extract_product_data(item)
      next if product_data[:asin].blank?

      asins_in_payload << product_data[:asin]

      begin
        product = Product.find_by(asin: product_data[:asin])
        # Incluir status active: reactiva productos que estaban desactivados en un run anterior
        product_data_with_status = product_data.merge(status: 'active')

        if product
          product.update!(product_data_with_status)
          updated_count += 1
        else
          product = Product.create!(product_data_with_status)
          created_count += 1
        end

        # Calcular y asignar min_weekly_payment
        price_usd = product_data[:price]
        if price_usd.present?
          min_payment = product.calculate_weekly_payment(
            weeks: nil,
            downpayment: nil,
            product_cost_usd: price_usd,
            used_credit: price_usd
          )
          product.update_column(:min_weekly_payment, min_payment)
        end

        # Procesar categorías del producto
        process_categories(product, item)

        # Procesar especificaciones del producto
        process_specifications(product, item)

        # Encolar job para descargar imágenes en segundo plano
        enqueue_image_download(product, item)
      rescue StandardError => e
        errors << { asin: product_data[:asin], error: e.message }
        Rails.logger.error "Error procesando producto #{product_data[:asin]}: #{e.message}"
      end
    end

    # Desactivar productos que ya existen en la DB pero no vinieron en este payload
    deactivated_count = Product.where.not(asin: asins_in_payload).update_all(status: 'inactive')

    Rails.logger.info "Procesamiento completado: #{created_count} creados, #{updated_count} actualizados, #{deactivated_count} desactivados (no en payload), #{errors.size} errores"
  end

  private

  # Detecta el tipo de respuesta y extrae el array de productos
  def extract_products_array(data)
    # Si ya es un array, retornarlo directamente
    return data if data.is_a?(Array)

    # Si es un hash con download_links, descargar y procesar
    if data.is_a?(Hash) && data.dig('result_set', 'download_links', 'json', 'all_pages').present?
      download_url = data.dig('result_set', 'download_links', 'json', 'all_pages')
      Rails.logger.info "Detectada respuesta con download_links. Descargando desde: #{download_url}"

      return download_and_extract_products(download_url)
    end

    Rails.logger.warn "Formato de datos no reconocido"
    nil
  end

  # Descarga el ZIP, lo descomprime y extrae el JSON de productos
  def download_and_extract_products(zip_url)
    Dir.mktmpdir do |tmp_dir|
      zip_path = File.join(tmp_dir, 'products.zip')

      # Descargar el archivo ZIP
      Rails.logger.info "Descargando archivo ZIP..."
      download_file(zip_url, zip_path)

      # Descomprimir y leer el JSON
      Rails.logger.info "Descomprimiendo archivo..."
      products_array = extract_json_from_zip(zip_path)

      Rails.logger.info "Extracción completada. #{products_array&.size || 0} productos encontrados."
      products_array
    end
  rescue StandardError => e
    Rails.logger.error "Error descargando/procesando ZIP: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end

  # Descarga un archivo desde una URL
  def download_file(url, destination)
    URI.open(url, 'rb') do |remote_file|
      File.open(destination, 'wb') do |local_file|
        local_file.write(remote_file.read)
      end
    end
  end

  # Extrae y parsea el JSON del archivo ZIP
  def extract_json_from_zip(zip_path)
    products = []

    Zip::File.open(zip_path) do |zip_file|
      zip_file.each do |entry|
        # Solo procesar archivos .json
        next unless entry.name.end_with?('.json')

        Rails.logger.info "Procesando archivo: #{entry.name}"

        # Extraer y leer el contenido
        json_content = entry.get_input_stream.read
        parsed_data = JSON.parse(json_content)

        # El JSON debe ser un array directamente
        if parsed_data.is_a?(Array)
          products.concat(parsed_data)
        end
      end
    end

    products
  end

  def extract_product_data(item)
    product = item.dig('result', 'product') || {}
    buybox = product['buybox_winner'] || {}
    price_info = buybox['price'] || {}

    {
      title: sanitize_text(product['title']),
      keywords: sanitize_text(product['keywords']),
      asin: sanitize_text(product['asin']),
      original_link: sanitize_text(product['link']),
      brand: sanitize_text(product['brand']),
      rating: product['rating'],
      feature_bullets: format_feature_bullets(product['feature_bullets']),
      original_price: price_info['value'],
      price: convert_to_usd(price_info['value'], price_info['currency']),
      currency: sanitize_text(price_info['currency']),
      color: sanitize_text(product['color']),
      material: sanitize_text(product['material']),
      dimensions: sanitize_text(product['dimensions']),
      model_number: sanitize_text(product['model_number']),
      external_id: sanitize_text(item['id'])
    }
  end

  def process_categories(product, item)
    categories_data = item.dig('result', 'product', 'categories') || []

    # Filtrar solo categorías que tienen category_id
    valid_categories = categories_data.select { |cat| cat['category_id'].present? }

    return if valid_categories.blank?

    current_category_ids = []

    valid_categories.each do |cat_data|
      category = upsert_category(cat_data)
      next unless category

      current_category_ids << category.id

      # Crear la relación ProductCategory si no existe
      begin
        ProductCategory.find_or_create_by(product: product, category: category)
      rescue StandardError => e
        Rails.logger.error "Error creando relación producto-categoría (producto: #{product.asin}, categoría: #{category.external_id}): #{e.message}"
      end
    end

    # Eliminar relaciones con categorías que ya no están en el array
    if current_category_ids.present?
      product.product_categories.where.not(category_id: current_category_ids).destroy_all
    end
  end

  def upsert_category(cat_data)
    external_id = sanitize_text(cat_data['category_id'])
    return nil if external_id.blank?

    category = Category.find_by(external_id: external_id)

    category_attrs = {
      name: sanitize_text(cat_data['name']),
      external_id: external_id,
      original_link: sanitize_text(cat_data['link'])
    }

    if category
      category.update!(category_attrs)
    else
      category = Category.create!(category_attrs)
    end

    category
  rescue StandardError => e
    Rails.logger.error "Error procesando categoría #{external_id}: #{e.message}"
    nil
  end

  def process_specifications(product, item)
    specifications = item.dig('result', 'product', 'specifications') || []
    bullets = format_specifications(specifications)

    return if bullets.blank?

    begin
      if product.specifications_list
        product.specifications_list.update!(bullets: bullets)
      else
        product.create_specifications_list!(bullets: bullets)
      end
    rescue StandardError => e
      Rails.logger.error "Error procesando especificaciones del producto #{product.asin}: #{e.message}"
    end
  end

  def format_specifications(specifications)
    return nil if specifications.blank?
    return nil unless specifications.is_a?(Array)

    specifications.map do |spec|
      name = sanitize_text(spec['name']) || 'Especificación'
      value = sanitize_text(spec['value'])
      next if name.blank? && value.blank?

      "#{name}: #{value}"
    end.compact.join("\n")
  end

  def enqueue_image_download(product, item)
    images = item.dig('result', 'product', 'images') || []
    return if images.blank?

    image_urls = images.map { |img| img['link'] }.compact
    return if image_urls.blank?

    ManageJson::DownloadProductImagesJob.perform_async(product.id, image_urls)
  end

  def format_feature_bullets(bullets)
    return nil if bullets.blank?
    return nil unless bullets.is_a?(Array)

    bullets.map { |bullet| sanitize_text(bullet) }.compact.join("\n")
  end

  def sanitize_text(value)
    return nil if value.nil?
    return value unless value.is_a?(String)

    # Eliminar caracter LEFT-TO-RIGHT MARK (U+200E)
    value.gsub("\u200E", '').strip
  end

  def convert_to_usd(price_value, currency)
    return nil if price_value.nil?

    if currency&.downcase == 'mxn'
      (price_value.to_f / ExchangeRate.current_rate).round(2)
    else
      price_value.to_f.round(2)
    end
  end
end
