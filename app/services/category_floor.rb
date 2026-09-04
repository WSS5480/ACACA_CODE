# frozen_string_literal: true

# ENGANCHE MÍNIMO POR CATEGORÍA — piso por TIPO DE ARTÍCULO (no por persona).
# Los departamentos se resuelven con el MISMO árbol de palabras clave que usan
# la tienda y el scraper (título + keywords + categorías). El piso de un
# carrito es el MÁS ALTO entre sus artículos y nunca baja del 10% base.
# Config: AppSetting 'category_down_floors' = {"Electrónica": 20, ...} (en %).
# Sin configuración => {} => todo queda en el 10% de siempre (apagado).
class CategoryFloor
  BASE_PCT = 10.0

  DEPTS = {
    'Electrónica' => ['Pantalla Smart TV', 'Barra de sonido', 'Bocina Bluetooth', 'Teatro en casa',
                      'Laptop', 'Computadora de escritorio', 'Monitor', 'Impresora', 'Tablet',
                      'Celular smartphone', 'Smartwatch', 'Audífonos', 'Cámara', 'Cámara de seguridad', 'Dron'],
    'Electrodomésticos' => ['Refrigerador', 'Lavadora', 'Secadora de ropa', 'Estufa', 'Congelador',
                            'Microondas', 'Licuadora', 'Freidora de aire', 'Cafetera', 'Batidora', 'Olla express',
                            'Aire acondicionado', 'Minisplit', 'Ventilador', 'Calefactor'],
    'Hogar y muebles' => ['Sala sofá', 'Comedor', 'Cama matrimonial', 'Ropero clóset', 'Escritorio', 'Librero',
                          'Colchón matrimonial', 'Colchón individual', 'Base de cama', 'Almohada'],
    'Herramientas' => ['Taladro', 'Esmeriladora', 'Sierra eléctrica', 'Lijadora',
                       'Kit de herramientas', 'Caja de herramientas', 'Compresor de aire'],
    'Cuidado personal' => ['Secadora de cabello', 'Plancha para cabello',
                           'Rasuradora eléctrica', 'Cepillo dental eléctrico', 'Depiladora']
  }.freeze

  class << self
    def floors
      raw = JSON.parse(AppSetting.get('category_down_floors').to_s)
      raw.is_a?(Hash) ? raw : {}
    rescue StandardError
      {}
    end

    def norm(s)
      I18n.transliterate(s.to_s).downcase.gsub(/[^a-z0-9 ]/, ' ').squeeze(' ').strip
    end

    def department_for(product)
      cats = product.respond_to?(:categories) ? (product.categories.map(&:name).join(' ') rescue '') : ''
      kw = product.respond_to?(:keywords) ? product.keywords : nil
      hay = norm([product.title, kw, cats].compact.join(' '))
      DEPTS.each do |dept, subs|
        subs.each do |sub|
          ns = norm(sub)
          return dept if hay.include?(ns)

          t = ns.split(' ').first
          return dept if t && t.length >= 4 && hay.include?(t)
        end
      end
      nil
    end

    def pct_for(product)
      dept = department_for(product)
      pct = dept ? floors[dept].to_f : 0.0
      [pct, BASE_PCT].max
    end

    def pct_for_products(products)
      ([BASE_PCT] + Array(products).compact.map { |p| pct_for(p) }).max
    end
  end
end
