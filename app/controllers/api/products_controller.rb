class Api::ProductsController < ApplicationController
  include TokenAuthenticatable
  include Paginatable
  include Searchable

  # Desactivar autenticación solo para acciones públicas
  skip_before_action :authenticate_entity!, only: [:index, :show, :manage_collection]

  before_action :set_product, only: [:show, :update, :destroy]
  before_action :authorize_master!, only: [:reset]

  # GET /api/products
  def index
    render_paginated(filtered_products(Product.all), ProductSerializer, 'title')
  end

  # GET /api/products/:id
  def show
    render json: ProductDetailSerializer.new(@product).serializable_hash, status: :ok
  end

  # PATCH/PUT /api/products/:id
  def update
    if @product.update(product_params)
      recalculate_weekly_payment_if_needed
      render json: ProductSerializer.new(@product.reload).serializable_hash, status: :ok
    else
      render json: { errors: @product.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/products/:id
  def destroy
    @product.destroy
    head :no_content
  end

  # POST /api/products/manage_collection
  def manage_collection
    # Forzar formato JSON (Rainforest no siempre envía Content-Type correcto)
    request.format = :json

    payload = extract_rainforest_payload

    unless payload.present?
      return render json: { error: 'El payload es requerido. Debe ser un array de productos o un objeto con download_links' }, status: :bad_request
    end

    if ExchangeRate.current_rate <= 0
      return render json: { error: 'No se puede procesar productos: se requiere un tipo de cambio válido' }, status: :unprocessable_entity
    end

    # Log para debugging de webhooks de Rainforest (solo Formato 2: hash con result_set/collection)
    if payload.is_a?(Hash)
      Rails.logger.info("[rainforest] result_set=#{payload.dig('result_set', 'id')} collection=#{payload.dig('collection', 'id')}")
    else
      Rails.logger.info("[rainforest] payload=array size=#{payload.size}")
    end

    # Encolar el job para procesar los productos en segundo plano
    ManageJson::ProcessProductsJob.perform_async(payload.as_json)

    # Responder 200 OK inmediatamente (Rainforest requiere 200, no acepta 202)
    render json: { ok: true }, status: :ok
  end

  # DELETE /api/products/reset
  def reset
    deleted_count = Product.count
    Product.destroy_all
    render json: { message: "#{deleted_count} productos eliminados exitosamente" }, status: :ok
  end

  # GET /api/products/download_csv
  def download_csv
    products = Product.includes(:categories)
    csv_data = ProductCsvExporterService.call(filtered_products(products))
    filename = "catalogo_productos_#{Date.current.strftime('%Y%m%d')}.csv"

    send_data csv_data,
              filename: filename,
              type: 'text/csv; charset=utf-8',
              disposition: 'attachment'
  end

  # POST /api/products/update_csv
  def update_csv
    unless params[:file].present?
      return render json: { error: 'El archivo CSV es requerido' }, status: :bad_request
    end

    unless valid_csv_file?(params[:file])
      return render json: { error: 'El archivo debe ser de tipo CSV' }, status: :bad_request
    end

    csv_content = params[:file].read

    # Generar un ID único para trackear el job
    job_id = SecureRandom.uuid

    # Encolar el job para procesar el CSV en segundo plano
    Products::ImportCsvJob.perform_async(job_id, csv_content)

    render json: {
      message: 'El archivo CSV se está procesando en segundo plano',
      job_id: job_id,
      status: 'processing'
    }, status: :accepted
  end

  # GET /api/products/track_csv_job/:job_id
  def track_csv_job
    job_id = params[:job_id]

    unless job_id.present?
      return render json: { error: 'El job_id es requerido' }, status: :bad_request
    end

    result = Products::ImportCsvJob.fetch_result(job_id)

    if result.nil?
      # Si no se encuentra, asumimos que ya terminó exitosamente y expiró
      render json: {
        status: 'completed',
        message: 'El proceso ha finalizado exitosamente',
        result: {
          note: 'Los detalles del resultado ya no están disponibles'
        }
      }, status: :ok
    else
      render json: result, status: :ok
    end
  end

  private

  def valid_csv_file?(file)
    return false unless file.respond_to?(:content_type)

    valid_types = ['text/csv', 'application/csv', 'text/plain', 'application/vnd.ms-excel']
    valid_types.include?(file.content_type) || file.original_filename&.end_with?('.csv')
  end

  # Extrae el payload de Rainforest según el formato recibido
  # - Array: formato directo de productos [{ "success": true, "result": {...} }, ...]
  # - Hash con download_links: formato con URLs de descarga
  def extract_rainforest_payload
    # Formato 1: Array directo de productos (params[:_json])
    if params[:_json].present? && params[:_json].is_a?(Array)
      return params[:_json]
    end

    # Formato 2: Hash con download_links (Rainforest envía esto para colecciones grandes)
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
      weeks: nil,
      downpayment: nil,
      product_cost_usd: @product.effective_price,
      used_credit: @product.effective_price
    )

    @product.update_column(:min_weekly_payment, new_weekly_payment)
  end
end

