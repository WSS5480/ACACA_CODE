# frozen_string_literal: true

# MONEDA DE COBRO — dólares (Stripe EE. UU.) o pesos (Stripe México).
#
# REGLA DE ORO: el contrato, el saldo, las cuotas y la contabilidad SIEMPRE
# están en dólares. Lo único que cambia es la moneda con la que se cobra la
# tarjeta. Si el cliente paga en pesos, aquí se convierte el total en USD a
# MXN con el tipo de cambio del día (ExchangeRate, que se refresca solo al
# mediodía) más un margen que cubre la comisión de Stripe México y la
# conversión posterior de pesos a dólares.
#
# El margen es configurable sin tocar código: FX_MARKUP_PCT en Render
# (por omisión 3). Poner 0 = tipo de cambio del día tal cual.
module PayCurrency
  DEFAULT        = 'usd'
  SUPPORTED      = %w[usd mxn].freeze
  DEFAULT_MARKUP = 3.0
  # Cada moneda se cobra en SU cuenta de Stripe (llaves distintas en Render).
  ACCOUNT_OF     = { 'usd' => 'us', 'mxn' => 'mx' }.freeze
  LABEL          = { 'usd' => 'USD', 'mxn' => 'MXN' }.freeze

  # 'MXN', :mxn, 'Pesos' -> 'mxn'; cualquier cosa desconocida -> 'usd'.
  def self.normalize(currency)
    c = currency.to_s.strip.downcase
    SUPPORTED.include?(c) ? c : DEFAULT
  end

  def self.account_of(currency)
    ACCOUNT_OF.fetch(normalize(currency), 'us')
  end

  def self.label(currency)
    LABEL.fetch(normalize(currency), 'USD')
  end

  # ¿Se puede cobrar en esta moneda AHORA MISMO? Pesos exige las llaves de
  # Stripe México en Render y un tipo de cambio válido en la base.
  def self.enabled?(currency)
    cur = normalize(currency)
    return StripeClient.configured?('us') if cur == 'usd'

    StripeClient.configured?('mx') && base_rate.positive?
  end

  def self.available
    SUPPORTED.select { |c| enabled?(c) }
  end

  # OJO: un valor mal escrito NO puede volverse 0% en silencio (sería regalar el
  # margen sin que nadie se entere): solo se acepta un número entre 0 y 25.
  def self.markup_pct
    v = ENV['FX_MARKUP_PCT'].to_s.strip
    return DEFAULT_MARKUP if v.empty?
    unless v.match?(/\A\d+(\.\d+)?\z/)
      Rails.logger.warn "[PayCurrency] FX_MARKUP_PCT inválido (#{v.inspect}); se usa #{DEFAULT_MARKUP}%" if defined?(Rails)
      return DEFAULT_MARKUP
    end

    f = v.to_f
    f <= 25 ? f : DEFAULT_MARKUP
  end

  # Tipo de cambio del día (mid-market) sin margen.
  def self.base_rate
    return 0.0 unless defined?(ExchangeRate) && ExchangeRate.table_exists?

    ExchangeRate.current_rate.to_f
  rescue StandardError
    0.0
  end

  # Tipo de cambio QUE SE COBRA (con margen). En dólares siempre es 1.
  def self.rate(currency)
    return 1.0 if normalize(currency) == 'usd'

    r = base_rate
    return 0.0 unless r.positive?

    (r * (1 + (markup_pct / 100.0))).round(4)
  end

  # Total en USD -> importe a cobrar en la moneda elegida.
  # Devuelve [importe (2 decimales), tipo de cambio usado].
  def self.convert(usd_amount, currency)
    cur = normalize(currency)
    return [usd_amount.to_f.round(2), 1.0] if cur == 'usd'

    r = rate(cur)
    raise ArgumentError, 'Sin tipo de cambio disponible para cobrar en pesos' unless r.positive?

    [(usd_amount.to_f * r).round(2), r]
  end

  # Importe en la unidad mínima que espera Stripe (centavos / centavos de peso).
  def self.smallest_unit(amount, _currency = nil)
    (amount.to_f * 100).round
  end

  # Todo lo que la tienda necesita para pintar el selector de moneda.
  def self.config
    {
      default: DEFAULT,
      available: available,
      markup_pct: markup_pct,
      rates: SUPPORTED.index_with { |c| rate(c) },
      base_rate: base_rate
    }
  end

  # Texto para el recibo y la bitácora: "MXN $1,234.56 al tipo de cambio 18.9500".
  def self.charge_note(amount_native, currency, rate_used)
    cur = normalize(currency)
    return nil if cur == 'usd'

    format('cobrado en %s $%s al tipo de cambio %s', label(cur),
           ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', amount_native)), format('%.4f', rate_used))
  end
end
