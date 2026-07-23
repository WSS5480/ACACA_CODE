require 'net/http'
require 'uri'

class Api::ProductsController < ApplicationController
  include TokenAuthenticatable
  include Paginatable
  include Searchable

  skip_before_action :authenticate_entity!, only: [:index, :show, :manage_collection]

  before_action :set_product, only: [:show, :update, :destroy]
  before_action :authorize_master!, only: [:reset]

  def index
    render_paginated(filtered_products(Product.all), ProductSerializer, 'title')
  end

  def show
    render json: ProductDetailSerializer.new(@product).serializable_hash, status: :ok
  end

  def update
    if @product.update(product_params)
      recalculate_weekly_payment_if_needed
      render json: ProductSerializer.new(@product.reload).serializable_hash, status: :ok
    else
      render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @product.destroy
    head :no_content
  end

  def manage_collection
    request.format = :json
    payload = extract_rainforest_payload

    unless payload.present?
      return render json: { error: 'El payload es requerido. Debe ser un array de productos o un objeto con download_links' }, status: :bad_request
    end

    if ExchangeRate.current_rate <= 0
      return render json: { error: 'No se puede procesar productos: se requiere un tipo de cambio valido' }, status: :unprocessable_entity
    end

    if payload.is_a?(Hash)
      Rails.logger.info("[rainforest] result_set=#{payload.dig('result_set', 'id')} collection=#{payload.dig('collection', 'id')}")
    else
      Rails.logger.info("[rainforest] payload=array size=#{payload.size}")
    end

    ManageJson::ProcessProductsJob.perform_async(payload.as_json)
    render json: { ok: true }, status: :ok
  end

  def import_search
    if ExchangeRate.current_rate <= 0
      return render json: { error: 'Se requiere un tipo de cambio valido antes de importar.' }, status: :unprocessable_entity
    end

    result = RainforestImportService.new.search_and_import(
      search_term: params[:search_term].to_s.strip,
      amazon_domain: params[:amazon_domain].presence || 'amazon.com',
      sold_only: params[:sold_only].to_s != 'false',
      delivered_only: params[:delivered_only].to_s != 'false'
    )

    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # POST /api/products/rainforest_category  { category_id }
  # Vista previa de una categoría/más-vendidos de Amazon (sin importar todavía).
  def rainforest_category
    result = RainforestImportService.new.category_preview(
      category_id: params[:category_id].to_s.strip,
      amazon_domain: params[:amazon_domain].presence || 'amazon.com.mx',
      limit: params[:limit].present? ? [[params[:limit].to_i, 1].max, 100].min : 50
    )
    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # POST /api/products/rainforest_search  { search_term, min_price?, max_price? }
  # Vista previa por PALABRA CLAVE con rango de precio opcional (sin importar todavía).
  def rainforest_search
    result = RainforestImportService.new.search_preview(
      search_term: params[:search_term].to_s.strip,
      amazon_domain: params[:amazon_domain].presence || 'amazon.com.mx',
      min_price: params[:min_price],
      max_price: params[:max_price],
      limit: params[:limit].present? ? [[params[:limit].to_i, 1].max, 100].min : 50
    )
    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # POST /api/products/check_sellers  { asins: [...] }
  # Verifica vendedor/envío por Amazon (1 crédito c/u) para pintar insignias en la vista previa.
  def check_sellers
    result = RainforestImportService.new.check_sellers(
      asins: params[:asins],
      amazon_domain: params[:amazon_domain].presence || 'amazon.com.mx'
    )
    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # POST /api/products/import_selected  { asins: [...] }
  # Importa como borrador SOLO los ASINs elegidos, con detalle completo.
  def import_selected
    if ExchangeRate.current_rate <= 0
      return render json: { error: 'Se requiere un tipo de cambio valido antes de importar.' }, status: :unprocessable_entity
    end

    result = RainforestImportService.new.import_selected(
      asins: params[:asins],
      amazon_domain: params[:amazon_domain].presence || 'amazon.com.mx',
      sold_only: params[:sold_only].to_s == 'true',
      delivered_only: params[:delivered_only].to_s == 'true',
      keywords: params[:keywords]
    )
    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # GET /api/products/rainforest_categories  { parent_id? }
  # Lista las categorías de más-vendidos válidas para poblar el dropdown.
  def rainforest_categories
    result = RainforestImportService.new.bestseller_categories(
      amazon_domain: params[:amazon_domain].presence || 'amazon.com.mx',
      parent_id: params[:parent_id].presence
    )
    render json: result, status: (result[:ok] ? :ok : :unprocessable_entity)
  end

  # POST /api/products/verify_availability  { id | ids: [...] }
  # Revisa si cada producto SIGUE publicado en Amazon consultando su página directamente
  # (NO usa Rainforest, NO gasta créditos). available=false => ya no está (marcar en rojo).
  def verify_availability
    ids = params[:ids].present? ? Array(params[:ids]) : (params[:id].present? ? [params[:id]] : nil)
    return render json: { error: 'Falta id o ids.' }, status: :bad_request if ids.blank?

    results = ids.map do |pid|
      product = Product.find_by(id: pid)
      next { id: pid, available: nil, reason: 'no encontrado' } unless product
      check_amazon_availability(product).merge(id: product.id)
    end
    render json: { ok: true, results: results }, status: :ok
  end

  def import_file
    return render json: { error: 'Se requiere un archivo.' }, status: :bad_request unless params[:file].present?

    if ExchangeRate.current_rate <= 0
      return render json: { error: 'Se requiere un tipo de cambio valido antes de importar.' }, status: :unprocessable_entity
    end

    parsed = (JSON.parse(params[:file].read) rescue nil)
    return render json: { error: 'El archivo debe ser JSON valido de Rainforest.' }, status: :unprocessable_entity if parsed.nil?

    array = parsed.is_a?(Array) ? parsed : (parsed['results'] || parsed['search_results'] || parsed['products'] || parsed['data'] || [parsed])
    items = Array(array).filter_map do |item|
      next unless item.is_a?(Hash)
      product = item.dig('result', 'product') || item['product'] || (item['asin'] ? item : nil)
      next unless product.is_a?(Hash) && product['asin'].present?
      product = product.merge('buybox_winner' => { 'price' => product['price'] }) if product['buybox_winner'].blank? && product['price'].present?
      { 'success' => true, 'id' => (item['id'] || product['asin']), 'result' => { 'product' => product } }
    end
    return render json: { error: 'No se encontraron productos en el archivo.' }, status: :unprocessable_entity if items.blank?

    ManageJson::ProcessProductsJob.perform_async(items, false, 'inactive')
    render json: { ok: true, received: items.size }, status: :ok
  end

  def bulk_update
    scope = bulk_scope
    return render json: { error: 'Nada que actualizar.' }, status: :bad_request if scope.nil?

    status = params[:status].to_s
    return render json: { error: 'Estatus invalido.' }, status: :unprocessable_entity unless %w[active inactive].include?(status)

    count = scope.update_all(status: status)
    render json: { ok: true, updated: count }, status: :ok
  end

  def bulk_delete
    scope = bulk_scope
    return render json: { error: 'Nada que eliminar.' }, status: :bad_request if scope.nil?

    count = scope.count
    scope.destroy_all
    render json: { ok: true, deleted: count }, status: :ok
  end

  def reset
    deleted_count = Product.count
    Product.destroy_all
    render json: { message: "#{deleted_count} productos eliminados exitosamente" }, status: :ok
  end

  def download_csv
    products = Product.includes(:categories)
    csv_data = ProductCsvExporterService.call(filtered_products(products))
    filename = "catalogo_productos_#{Date.current.strftime('%Y%m%d')}.csv"

    send_data csv_data, filename: filename, type: 'text/csv; charset=utf-8', disposition: 'attachment'
  end

  def update_csv
    unless params[:file].present?
      return render json: { error: 'El archivo CSV es requerido' }, status: :bad_request
    end

    unless valid_csv_file?(params[:file])
      return render json: { error: 'El archivo debe ser de tipo CSV' }, status: :bad_request
    end

    csv_content = params[:file].read
    job_id = SecureRandom.uuid
    Products::ImportCsvJob.perform_async(job_id, csv_content)

    render json: { message: 'El archivo CSV se esta procesando en segundo plano', job_id: job_id, status: 'processing' }, status: :accepted
  end

  def track_csv_job
    job_id = params[:job_id]

    unless job_id.present?
      return render json: { error: 'El job_id es requerido' }, status: :bad_request
    end

    result = Products::ImportCsvJob.fetch_result(job_id)

    if result.nil?
      render json: { status: 'completed', message: 'El proceso ha finalizado exitosamente', result: { note: 'Los detalles del resultado ya no estan disponibles' } }, status: :ok
    else
      render json: result, status: :ok
    end
  end

  private

  # Consulta la página de Amazon del producto SIN Rainforest (sin créditos).
  # Devuelve { available:, code:, reason: }. available=nil => no se pudo determinar (no marcar).
  def check_amazon_availability(product)
    asin = product.asin.to_s.strip
    url = product.original_link.presence || (asin.present? ? "https://www.amazon.com.mx/dp/#{asin}" : nil)
    return { available: nil, code: 0, reason: 'sin link/asin' } if url.blank?

    current = url
    3.times do
      uri = URI.parse(current)
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36'
      req['Accept-Language'] = 'es-MX,es;q=0.9'
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 12) { |http| http.request(req) }

      case res
      when Net::HTTPNotFound
        return { available: false, code: 404, reason: '404 no encontrado' }
      when Net::HTTPRedirection
        current = URI.join(current, res['location'].to_s).to_s
        next
      when Net::HTTPSuccess
        low = res.body.to_s.downcase
        gone_markers = ['página no encontrada', 'pagina no encontrada', 'no está disponible', 'no esta disponible',
                        'currently unavailable', 'no disponible actualmente', 'dogs of amazon', 'perritos de amazon']
        gone = gone_markers.any? { |m| low.include?(m) }
        asin_present = asin.blank? || low.include?(asin.downcase)
        available = !gone && asin_present
        return { available: available, code: res.code.to_i, reason: (gone ? 'marcado no disponible' : (asin_present ? 'ok' : 'asin ausente en la página')) }
      else
        # 503/CAPTCHA/bloqueo => no se pudo determinar; no marcar en rojo.
        return { available: nil, code: res.code.to_i, reason: "respuesta #{res.code}" }
      end
    end
    { available: nil, code: 0, reason: 'demasiados redirecciones' }
  rescue StandardError => e
    { available: nil, code: 0, reason: e.message }
  end

  def valid_csv_file?(file)
    return false unless file.respond_to?(:content_type)

    valid_types = ['text/csv', 'application/csv', 'text/plain', 'application/vnd.ms-excel']
    valid_types.include?(file.content_type) || file.original_filename&.end_with?('.csv')
  end

  def extract_rainforest_payload
    if params[:_json].present? && params[:_json].is_a?(Array)
      return params[:_json]
    end

    if params[:result_set].present? && params.dig(:result_set, :download_links, :json, :all_pages).present?
      return params.to_unsafe_h.except(:controller, :action)
    end

    nil
  end

  def authorize_master!
    unless ['master', 'admin'].include?(@current_user&.role&.name)
      render json: { error: 'No autorizado. Se requiere rol master.' }, status: :forbidden
    end
  end

  def set_product
    @product = Product.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Producto no encontrado' }, status: :not_found
  end

  def product_params
    params.require(:product).permit(
      :title, :keywords, :asin, :original_link, :brand, :rating,
      :feature_bullets, :price, :price_with_discount, :currency, :color, :material,
      :dimensions, :model_number, :external_id, :status,
      :min_weekly_payment, :turns, :decimal_factor, :original_price,
      category_ids: []
    )
  end

  def bulk_scope
    ids =
      if params[:ids].present?
        Array(params[:ids])
      elsif params[:category_id].present?
        Product.joins(:product_categories)
               .where(product_categories: { category_id: params[:category_id] })
               .distinct.pluck(:id)
      end
    ids && Product.where(id: ids)
  end

  def filtered_products(input_products)
    products = input_products.present? ? input_products : Product.all
    products = apply_search_filter(products, columns: %w[title keywords asin brand])
    products = filter_by_category(products)
    products = filter_by_status(products)
    products = filter_by_weekly_payment_range(products)
    products = products.where.not(price_with_discount: nil) if params[:with_discount].present? && params[:with_discount] == 'true'
    order_by_weekly_payment(products)
  end

  def filter_by_status(products)
    return products unless params[:status].present?

    status = params[:status].to_s.downcase.strip
    return products unless %w[active inactive].include?(status)

    products.where(status: status)
  end

  def filter_by_category(products)
    return products unless params[:category_ids].present?

    category_external_ids = Array(params[:category_ids])
    categories = Category.where(external_id: category_external_ids)
    return products.none unless categories.exists?

    products.joins(:categories).where(categories: { id: categories.pluck(:id) }).distinct
  end

  def filter_by_weekly_payment_range(products)
    return products unless params[:weekly_payment_range].present?

    range_values = params[:weekly_payment_range].to_s.split('-')
    return products unless range_values.length == 2

    min_value = range_values[0].to_d
    max_value = range_values[1].to_d

    products.where(min_weekly_payment: min_value..max_value)
  end

  def order_by_weekly_payment(products)
    return products unless params[:weekly_payment_order].present?

    direction = params[:weekly_payment_order].to_s.downcase
    return products unless %w[asc desc].include?(direction)

    products.order(min_weekly_payment: direction.to_sym)
  end

  def recalculate_weekly_payment_if_needed
    pricing_fields_changed = @product.saved_change_to_price? ||
                             @product.saved_change_to_price_with_discount? ||
                             @product.saved_change_to_decimal_factor? ||
                             @product.saved_change_to_turns?

    return unless pricing_fields_changed && @product.effective_price.present?

    new_weekly_payment = @product.calculate_weekly_payment(
      weeks: nil, downpayment: nil,
      product_cost_usd: @product.effective_price,
      used_credit: @product.effective_price
    )

    @product.update_column(:min_weekly_payment, new_weekly_payment)
  end
end
