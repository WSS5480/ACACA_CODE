# frozen_string_literal: true

require 'net/http'
require 'json'

# Verifica que un CP/ZIP corresponda a la ciudad y estado capturados,
# CONTRA DATOS REALES: primero la tabla zip_codes (SEPOMEX / caché),
# y si el código no está, lo consulta en api.zippopotam.us (datos oficiales
# de correos de EUA y México) y guarda el resultado en zip_codes como caché.
#
# Devuelve:
#   { status: 'match' }
#   { status: 'mismatch', expected_city:, expected_state:, state_ok:, city_ok: }
#   { status: 'unknown' }   (CP no encontrado o sin datos suficientes; no se alerta)
class ZipLookup
  TIMEOUT = 6

  def self.check(country:, zip:, city:, state:)
    z = zip.to_s.gsub(/\D/, '')
    return { status: 'unknown' } if z.length < 4
    z = z.rjust(5, '0') if z.length == 4 # CP de México con cero inicial perdido
    return { status: 'unknown' } if city.blank? && state.blank?

    rows = ZipCode.where(code: z).where('upper(country) = ?', country.to_s.upcase).to_a
    rows = fetch_and_cache(country, z) if rows.empty?
    return { status: 'unknown' } if rows.empty?

    exp_states = rows.flat_map { |r| [r.state_name, r.state_initials] }.reject(&:blank?).uniq
    exp_cities = rows.flat_map { |r| [r.city, r.municipality, r.settlement] }.reject(&:blank?).uniq

    state_ok = state.blank? || exp_states.any? { |s| same?(s, state) }
    city_ok  = city.blank? || exp_cities.empty? || exp_cities.any? { |c| same?(c, city) }

    return { status: 'match' } if state_ok && city_ok

    first = rows.first
    {
      status: 'mismatch',
      expected_city: first.city.presence || first.municipality.presence || first.settlement.presence,
      expected_state: first.state_name.presence || first.state_initials.presence,
      state_ok: state_ok,
      city_ok: city_ok
    }
  rescue StandardError => e
    Rails.logger.warn "[zip_lookup] #{e.class}: #{e.message}"
    { status: 'unknown' }
  end

  # Comparación tolerante: sin acentos, sin mayúsculas, y acepta contenido parcial
  # ("Dallas" vs "Dallas County", "CDMX" vs "Ciudad de Mexico" no coinciden y sí alertan).
  def self.same?(a, b)
    na = norm(a)
    nb = norm(b)
    return false if na.empty? || nb.empty?

    na == nb || na.include?(nb) || nb.include?(na)
  end

  def self.norm(s)
    I18n.transliterate(s.to_s).downcase.gsub(/[^a-z0-9 ]/, ' ').squeeze(' ').strip
  end

  def self.fetch_and_cache(country, zip)
    cc = country.to_s.downcase
    uri = URI("https://api.zippopotam.us/#{cc}/#{zip}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    res = http.get(uri.path)
    return [] unless res.is_a?(Net::HTTPSuccess)

    places = (JSON.parse(res.body)['places'] || [])
    return [] if places.empty?

    places.first(20).map do |pl|
      ZipCode.create!(
        country: country.to_s.upcase,
        code: zip,
        state_name: pl['state'],
        state_initials: pl['state abbreviation'],
        # EUA: "place name" es la ciudad. MX: "place name" es la colonia (settlement).
        city: cc == 'us' ? pl['place name'] : nil,
        settlement: cc == 'us' ? nil : pl['place name']
      )
    end
  rescue StandardError => e
    Rails.logger.warn "[zip_lookup] fetch #{country}/#{zip}: #{e.message}"
    []
  end
end
