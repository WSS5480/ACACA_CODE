class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Almacén simple clave/valor para configuraciones editables desde el admin
  # (por ejemplo, la API key de Rainforest). No se expone el valor en claro.
  #
  # LECTURA UNA SOLA VEZ POR PETICIÓN: el catálogo pide la tasa de interés, el
  # factor de contado y los pisos de enganche muchas veces por producto. Antes
  # cada llamada era un SELECT; con 380 productos eso eran miles de consultas y
  # la tienda tardaba 7-8 segundos en abrir. Ahora la primera lectura de cada
  # clave se guarda en Current (que Rails limpia al terminar la petición), así
  # que el valor siempre es el de ESTA petición, nunca uno viejo.
  def self.get(key, default = nil)
    k = key.to_s
    cache = (Current.settings ||= {})
    cache[k] = find_by(key: k)&.value unless cache.key?(k)
    cache[k].presence || default
  rescue StandardError
    # Si Current no está disponible (consola, tareas sueltas), se lee directo.
    find_by(key: key)&.value.presence || default
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
    Current.settings&.delete(key.to_s)   # que el mismo request ya vea el valor nuevo
    record
  end

  # Tasa numérica configurable (Seguridad → Tasas e impuestos) con valor por defecto.
  def self.rate(key, default)
    v = get(key)
    v.present? ? v.to_f : default.to_f
  rescue StandardError
    default.to_f
  end
end
