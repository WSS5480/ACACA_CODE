# frozen_string_literal: true

# ENGANCHE MÍNIMO POR CATEGORÍA — piso por TIPO DE ARTÍCULO (no por persona).
# El departamento de un artículo es el PRIMER nivel de su ruta real de Amazon
# (product.categories: "Electrónicos > Televisión y Vídeo > Televisiones" =>
# "Electrónicos"), el mismo que se ve en el scraper y en la tienda. Antes se
# adivinaba con una lista de palabras escrita a mano, que no coincidía con los
# nombres de Amazon. El piso de un carrito es el MÁS ALTO entre sus artículos y
# nunca baja del 10% base.
# Config: AppSetting 'category_down_floors' = {"Electrónicos": 20, ...} (en %).
# Sin configuración => {} => todo queda en el 10% de siempre (apagado).
class CategoryFloor
  BASE_PCT = 10.0
  MAX_PCT = 90.0

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

    # Departamento = primer nivel de la ruta de Amazon del producto.
    def department_for(product)
      return nil unless product.respond_to?(:categories)

      (product.categories.map(&:name).find { |n| n.to_s.strip.present? }&.strip)
    rescue StandardError
      nil
    end

    # Departamentos que EXISTEN hoy en el catálogo (para la pantalla de pisos).
    # Se ordenan por cantidad de productos: primero los que más pesan.
    def departments
      return [] unless defined?(Product)

      conteo = Hash.new(0)
      Product.includes(:categories).find_each do |p|
        d = department_for(p)
        conteo[d] += 1 if d.present?
      end
      conteo.sort_by { |name, n| [-n, name] }.map(&:first)
    rescue StandardError
      []
    end

    # El piso guardado se busca por nombre exacto y, si no, sin acentos ni
    # mayúsculas (para que un nombre tecleado a mano siga sirviendo).
    def floor_for_name(name)
      return 0.0 if name.blank?

      f = floors
      return f[name].to_f if f.key?(name)

      objetivo = norm(name)
      par = f.find { |k, _| norm(k) == objetivo }
      par ? par[1].to_f : 0.0
    end

    def pct_for(product)
      [floor_for_name(department_for(product)), BASE_PCT].max
    end

    def pct_for_products(products)
      ([BASE_PCT] + Array(products).compact.map { |p| pct_for(p) }).max
    end
  end
end
