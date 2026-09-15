# frozen_string_literal: true

# PAÍSES ATENDIDOS. Configuración editable en el admin (Configuración → Países),
# guardada en app_settings['serving_countries'] como JSON:
#   { "allowed": [],               # vacío = cualquier país (menos los bloqueados)
#     "blocked": ["CU","IR","KP"], # se SUMAN a los sancionados de forma integral, que nunca se quitan
#     "caps":    { "ES": 500 } }    # tope de línea inicial por país (USD), opcional
# La usan el alta de clientes, el motor de riesgo (tope) y la pantalla de Países.
class ServingCountries
  KEY = 'serving_countries'

  def self.config
    raw = AppSetting.get(KEY)
    data = raw.present? ? JSON.parse(raw) : {}
    data = {} unless data.is_a?(Hash)
    {
      'allowed' => Array(data['allowed']).map { |c| c.to_s.upcase.strip }.reject(&:blank?).uniq,
      'blocked' => (Array(data['blocked']).map { |c| c.to_s.upcase.strip } + PhoneGeo::DEFAULT_BLOCKED).reject(&:blank?).uniq,
      'caps' => (data['caps'].is_a?(Hash) ? data['caps'].transform_keys { |k| k.to_s.upcase }.transform_values(&:to_f).select { |_, v| v.positive? } : {})
    }
  rescue StandardError
    { 'allowed' => [], 'blocked' => PhoneGeo::DEFAULT_BLOCKED.dup, 'caps' => {} }
  end

  def self.blocked?(iso)
    iso.present? && config['blocked'].include?(iso.to_s.upcase)
  end

  def self.allowed?(iso)
    return false if iso.blank? || blocked?(iso)

    allowed = config['allowed']
    allowed.empty? || allowed.include?(iso.to_s.upcase)
  end

  # nil si se puede atender; si no, el motivo en español para mostrarlo tal cual.
  def self.problem(iso, phone: nil)
    iso = iso.presence || PhoneGeo.country_of(phone)
    return nil if iso.blank? # sin país conocido no se bloquea (cuentas y flujos anteriores)
    return nil if allowed?(iso)

    name = PhoneGeo.name(iso).presence || iso.to_s.upcase
    "Por ahora no podemos abrir cuentas en #{name}. Si crees que es un error, escríbenos por WhatsApp."
  end

  # Tope de línea inicial para un país (USD) o nil si no hay tope configurado.
  def self.cap_for(iso)
    return nil if iso.blank?

    v = config['caps'][iso.to_s.upcase]
    v&.positive? ? v : nil
  end

  def self.save!(allowed:, blocked:, caps:)
    clean = lambda do |list|
      Array(list).flat_map { |v| v.to_s.split(/[\s,;]+/) }.map { |c| c.upcase.strip }.select { |c| PhoneGeo.country(c) }.uniq
    end
    caps_h = {}
    (caps.is_a?(Hash) ? caps : {}).each do |k, v|
      iso = k.to_s.upcase.strip
      next unless PhoneGeo.country(iso) && v.to_f.positive?

      caps_h[iso] = v.to_f.round(2)
    end
    value = { 'allowed' => clean.call(allowed), 'blocked' => (clean.call(blocked) + PhoneGeo::DEFAULT_BLOCKED).uniq, 'caps' => caps_h }
    AppSetting.set(KEY, JSON.generate(value))
    config
  end

  # Para el selector público del storefront: países atendidos con nombre y lada.
  def self.public_list
    cfg = config
    PhoneGeo::COUNTRIES.filter_map do |iso, (es, en, dial, _tz)|
      next if cfg['blocked'].include?(iso)
      next if cfg['allowed'].any? && !cfg['allowed'].include?(iso)

      { iso: iso, es: es, en: en, dial: dial }
    end
  end
end
