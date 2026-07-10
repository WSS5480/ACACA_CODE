require 'net/http'
require 'json'

# Obtiene el tipo de cambio USD -> MXN de una API pública y crea un
# ExchangeRate si el valor es válido y cambió respecto al último registrado.
#
# Se ejecuta automáticamente cada día mediante sidekiq-scheduler
# (ver config/sidekiq_schedule.yml). También puede ejecutarse manualmente:
#   ExchangeRates::FetchRateJob.perform_async
#
# La URL de la API es configurable con la variable de entorno
# EXCHANGE_RATE_API_URL. Por defecto usa open.er-api.com (sin API key).
class ExchangeRates::FetchRateJob
  include Sidekiq::Job

  sidekiq_options queue: 'default', retry: 3

  DEFAULT_API_URL = 'https://open.er-api.com/v6/latest/USD'.freeze

  def perform
    rate = fetch_usd_to_mxn

    if rate.nil? || rate <= 0
      Rails.logger.error('[exchange_rate] no se obtuvo un tipo de cambio válido; se conserva el anterior')
      return
    end

    rounded = rate.round(2)

    if ExchangeRate.current_rate.to_d == rounded.to_d
      Rails.logger.info("[exchange_rate] sin cambios (1 USD = #{rounded} MXN); no se crea registro nuevo")
      return
    end

    ExchangeRate.create!(usd_to_mxn: rounded)
    Rails.logger.info("[exchange_rate] nuevo tipo de cambio guardado: 1 USD = #{rounded} MXN")
  end

  private

  def fetch_usd_to_mxn
    url = URI(ENV.fetch('EXCHANGE_RATE_API_URL', DEFAULT_API_URL))

    response = Net::HTTP.start(
      url.host, url.port,
      use_ssl: url.scheme == 'https',
      open_timeout: 10, read_timeout: 10
    ) { |http| http.get(url.request_uri) }

    return nil unless response.is_a?(Net::HTTPSuccess)

    extract_rate(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.error("[exchange_rate] error al consultar la API: #{e.message}")
    nil
  end

  # Soporta las formas más comunes de respuesta:
  #   open.er-api.com / exchangerate-api  -> { "rates": { "MXN": .. } }
  #   exchangerate.host (v1)              -> { "conversion_rates": { "MXN": .. } }
  def extract_rate(data)
    rates = data['rates'] || data['conversion_rates'] || {}
    value = rates['MXN'] || rates['mxn']
    value&.to_f
  end
end
