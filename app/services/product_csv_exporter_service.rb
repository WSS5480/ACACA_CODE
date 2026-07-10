require 'csv'

class ProductCsvExporterService
  HEADERS = [
    'ID',
    'ASIN',
    'Título',
    'Marca',
    'Color',
    'Material',
    'Dimensiones',
    'Modelo',
    'Keywords',
    'Categorías',
    'Link original',
    'Precio original',
    'Moneda original',
    'Precio USD',
    'Precio con descuento USD',
    'Turns',
    'Factor decimal',
    'Estatus'
  ].freeze

  # Atributos simples del producto (antes de categorías)
  ATTRIBUTES_BEFORE_CATEGORIES = %i[
    id
    asin
    title
    brand
    color
    material
    dimensions
    model_number
    keywords
  ].freeze

  # Atributos simples del producto (después de categorías, excepto status)
  ATTRIBUTES_AFTER_CATEGORIES = %i[
    original_link
    original_price
    currency
    price
    price_with_discount
    turns
    decimal_factor
  ].freeze

  # Traducción de valores de status al español
  STATUS_TRANSLATIONS = {
    'active' => 'Activo',
    'inactive' => 'Desactivado'
  }.freeze

  def initialize(products)
    @products = products
  end

  def call
    generate_csv
  end

  def self.call(products)
    new(products).call
  end

  private

  # BOM (Byte Order Mark) para indicar a Excel que el archivo es UTF-8
  UTF8_BOM = "\xEF\xBB\xBF"

  def generate_csv
    csv_content = CSV.generate(headers: true) do |csv|
      csv << HEADERS
      @products.find_each do |product|
        csv << product_row(product)
      end
    end

    UTF8_BOM + csv_content
  end

  def product_row(product)
    before = ATTRIBUTES_BEFORE_CATEGORIES.map { |attr| product.public_send(attr) }
    categories = product.categories.map(&:name).join(', ')
    after = ATTRIBUTES_AFTER_CATEGORIES.map { |attr| product.public_send(attr) }
    status = translate_status(product.status)

    before + [categories] + after + [status]
  end

  def translate_status(status)
    STATUS_TRANSLATIONS[status] || status
  end
end
