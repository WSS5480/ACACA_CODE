require 'csv'

class ProductCsvImporterService
  # Mapeo de headers del CSV a atributos del modelo
  HEADER_TO_ATTRIBUTE = {
    'ID' => :id,
    'ASIN' => :asin,
    'Precio USD' => :price,
    'Precio con descuento USD' => :price_with_discount,
    'Turns' => :turns,
    'Factor decimal' => :decimal_factor,
    'Estatus' => :status
  }.freeze

  # Campos permitidos para actualización
  UPDATABLE_FIELDS = %i[price price_with_discount turns decimal_factor status].freeze

  # Valores válidos para status
  VALID_STATUSES = %w[active inactive].freeze

  # Traducción inversa de status (español -> inglés)
  STATUS_REVERSE_TRANSLATIONS = {
    'Activo' => 'active',
    'Desactivado' => 'inactive',
    'active' => 'active',
    'inactive' => 'inactive'
  }.freeze

  def initialize(csv_content)
    @csv_content = csv_content
    @results = {
      total_rows: 0,
      updated: 0,
      not_found: 0,
      skipped: 0,
      errors: []
    }
  end

  def call
    process_csv
    @results
  end

  def self.call(csv_content)
    new(csv_content).call
  end

  private

  def process_csv
    # Remover BOM si existe
    clean_content = remove_bom(@csv_content)

    csv = CSV.parse(clean_content, headers: true)
    @results[:total_rows] = csv.size

    csv.each_with_index do |row, index|
      process_row(row, index + 2) # +2 porque index empieza en 0 y hay header
    end
  rescue CSV::MalformedCSVError => e
    @results[:errors] << { row: 0, message: "CSV malformado: #{e.message}" }
  end

  def process_row(row, row_number)
    id = row['ID'].presence
    asin = row['ASIN'].presence

    unless asin
      @results[:skipped] += 1
      @results[:errors] << { row: row_number, message: 'ASIN vacío, fila ignorada' }
      return
    end

    product = find_product(id, asin)

    unless product
      @results[:not_found] += 1
      @results[:errors] << { row: row_number, asin: asin, message: 'Producto no encontrado' }
      return
    end

    update_product(product, row, row_number)
  end

  def find_product(id, asin)
    if id.present?
      # Buscar por ID y ASIN
      Product.find_by(id: id, asin: asin)
    else
      # Buscar solo por ASIN
      Product.find_by(asin: asin)
    end
  end

  def update_product(product, row, row_number)
    attributes = extract_updatable_attributes(row)

    if attributes.empty?
      @results[:skipped] += 1
      return
    end

    if product.update(attributes)
      recalculate_weekly_payment(product)
      @results[:updated] += 1
    else
      @results[:errors] << {
        row: row_number,
        asin: product.asin,
        message: "Error al actualizar: #{product.errors.full_messages.join(', ')}"
      }
    end
  rescue StandardError => e
    @results[:errors] << {
      row: row_number,
      asin: product&.asin,
      message: "Error inesperado: #{e.message}"
    }
  end

  def extract_updatable_attributes(row)
    attributes = {}

    # Extraer campos numéricos
    %w[price price_with_discount turns decimal_factor].each do |field|
      header = HEADER_TO_ATTRIBUTE.key(field.to_sym)
      value = row[header]
      attributes[field.to_sym] = parse_decimal(value) if value.present?
    end

    # Extraer y validar status
    status_value = row['Estatus']
    if status_value.present?
      translated_status = STATUS_REVERSE_TRANSLATIONS[status_value.strip]
      if translated_status && VALID_STATUSES.include?(translated_status)
        attributes[:status] = translated_status
      end
      # Si el status no es válido, simplemente no se incluye en los atributos
    end

    attributes
  end

  def parse_decimal(value)
    return nil if value.blank?

    # Manejar formatos con coma o punto decimal
    value.to_s.gsub(',', '.').to_d
  rescue StandardError
    nil
  end

  def recalculate_weekly_payment(product)
    return unless product.effective_price.present?

    new_weekly_payment = product.calculate_weekly_payment(
      weeks: nil,
      downpayment: nil,
      product_cost_usd: product.effective_price,
      used_credit: product.effective_price
    )

    product.update_column(:min_weekly_payment, new_weekly_payment)
  end

  def remove_bom(content)
    # Remover BOM de UTF-8 si existe
    content.sub(/\A\xEF\xBB\xBF/, '')
  end
end
