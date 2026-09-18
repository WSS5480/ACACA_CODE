# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

# Cliente minimo para la API REST de Stripe (sin gema).
#
# DOS CUENTAS DE STRIPE (ver PayCurrency):
#   'us' -> STRIPE_SECRET_KEY / STRIPE_PUBLISHABLE_KEY / STRIPE_WEBHOOK_SECRET
#           Cobros en DÓLARES. Es la cuenta de siempre: cualquier llamada que
#           no diga cuenta usa esta, así nada del código anterior cambia.
#   'mx' -> STRIPE_MX_SECRET_KEY / STRIPE_MX_PUBLISHABLE_KEY /
#           STRIPE_MX_WEBHOOK_SECRET. Cobros en PESOS.
# Cada cuenta tiene sus propios clientes, tarjetas guardadas y depósitos: una
# tarjeta guardada en México NO se puede cobrar desde la cuenta de EE. UU.
# Mientras no existan las llaves de México, el pago en pesos simplemente no se
# ofrece y todo funciona como antes.
class StripeClient
  BASE = 'https://api.stripe.com'
  ACCOUNTS = %w[us mx].freeze
  ENV_KEYS = {
    'us' => { secret: 'STRIPE_SECRET_KEY',    publishable: 'STRIPE_PUBLISHABLE_KEY',    webhook: 'STRIPE_WEBHOOK_SECRET' },
    'mx' => { secret: 'STRIPE_MX_SECRET_KEY', publishable: 'STRIPE_MX_PUBLISHABLE_KEY', webhook: 'STRIPE_MX_WEBHOOK_SECRET' }
  }.freeze

  # Error de Stripe con su código: el autopago distingue "la tarjeta fue
  # rechazada" de "el banco pide que el cliente confirme el cargo" (3-D Secure /
  # SCA, habitual en tarjetas europeas y de otros países fuera de EE. UU.).
  class Error < StandardError
    attr_reader :code, :decline_code, :http_status

    def initialize(msg = nil, code: nil, decline_code: nil, http_status: nil)
      super(msg)
      @code = code
      @decline_code = decline_code
      @http_status = http_status
    end

    # El banco emisor exige autenticación del titular: no es un rechazo, el
    # cliente debe entrar a la tienda y confirmar el pago con su banco.
    def authentication_required?
      code == 'authentication_required' || decline_code == 'authentication_required'
    end
  end

  def self.account(name = nil)
    n = name.to_s.strip.downcase
    ACCOUNTS.include?(n) ? n : 'us'
  end

  def self.env_key(kind, acct = 'us')
    ENV[ENV_KEYS.fetch(account(acct)).fetch(kind)].to_s
  end

  def self.secret_key(acct = 'us')  = env_key(:secret, acct).presence
  def self.webhook_secret(acct = 'us') = env_key(:webhook, acct).presence

  def self.publishable_key(acct = 'us')
    k = env_key(:publishable, acct).presence
    # Compatibilidad: la llave pública de EE. UU. también se aceptaba con el
    # nombre del frontend (NEXT_PUBLIC_…) cuando se pegó una sola vez en Render.
    k ||= ENV['NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY'].to_s.presence if account(acct) == 'us'
    k ||= ENV['NEXT_PUBLIC_STRIPE_MX_PUBLISHABLE_KEY'].to_s.presence if account(acct) == 'mx'
    k
  end

  # Una cuenta está lista cuando tiene su llave secreta (la pública solo la
  # necesita el navegador para pintar el formulario).
  def self.configured?(acct = 'us')
    secret_key(acct).present?
  end

  def self.accounts_status
    ACCOUNTS.index_with do |a|
      { configured: configured?(a), publishable_key: publishable_key(a).to_s, webhook: webhook_secret(a).present? }
    end
  end

  def self.request(method, path, params = nil, account: 'us')
    acct = self.account(account)
    key = secret_key(acct)
    raise Error, "Stripe #{acct.upcase} no esta configurado (#{ENV_KEYS.fetch(acct)[:secret]})" if key.blank?

    uri = URI("#{BASE}#{path}")
    req = case method
          when :get
            uri.query = URI.encode_www_form(flatten_params(params)) if params.present?
            Net::HTTP::Get.new(uri)
          when :post
            r = Net::HTTP::Post.new(uri)
            r.set_form_data(flatten_params(params || {}))
            r
          else
            raise Error, "Metodo no soportado: #{method}"
          end
    req['Authorization'] = "Bearer #{key}"
    req['Stripe-Version'] = '2024-06-20'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
    body = JSON.parse(res.body) rescue {}
    unless res.is_a?(Net::HTTPSuccess)
      msg = body.dig('error', 'message') || "Stripe HTTP #{res.code}"
      raise Error.new(msg, code: body.dig('error', 'code'), decline_code: body.dig('error', 'decline_code'), http_status: res.code.to_i)
    end
    body
  end

  # MÉTODOS DE PAGO GUARDADOS de un cliente, de cualquier tipo reutilizable
  # SIN el cliente presente (tarjeta o Link). Antes solo se listaban 'card':
  # una tarjeta guardada a través de Link (Stripe la registra como tipo
  # 'link') quedaba invisible — el Perfil decía "guarda una tarjeta primero" y
  # el autopago "necesitas una tarjeta guardada" aunque el alta hubiera sido
  # exitosa. Devuelve la más reciente primero y quita duplicados de la misma
  # tarjeta física (fingerprint) o del mismo Link (correo).
  REUSABLE_TYPES = %w[card link].freeze

  def self.saved_methods(customer_id, account: 'us')
    return [] if customer_id.blank?

    acct = self.account(account)
    res = request(:get, '/v1/payment_methods', { customer: customer_id, limit: 100 }, account: acct)
    seen = {}
    dupes = []
    (res['data'] || []).each do |pm|
      next unless REUSABLE_TYPES.include?(pm['type'])

      key = if pm['type'] == 'card'
              pm.dig('card', 'fingerprint').presence ||
                "#{pm.dig('card', 'brand')}-#{pm.dig('card', 'last4')}-#{pm.dig('card', 'exp_month')}-#{pm.dig('card', 'exp_year')}"
            else
              "link-#{pm.dig('link', 'email').to_s.downcase}"
            end
      if seen.key?(key)
        dupes << pm['id']
      else
        seen[key] = normalize_method(pm, acct)
      end
    end
    dupes.each do |id|
      request(:post, "/v1/payment_methods/#{id}/detach", {}, account: acct)
    rescue Error
      nil # si no se pudo desprender, igual queda fuera de la lista
    end
    seen.values
  end

  def self.normalize_method(pm, acct = 'us')
    currency = acct == 'mx' ? 'mxn' : 'usd'
    if pm['type'] == 'card'
      { id: pm['id'], type: 'card', brand: pm.dig('card', 'brand'), last4: pm.dig('card', 'last4'),
        exp_month: pm.dig('card', 'exp_month'), exp_year: pm.dig('card', 'exp_year'),
        account: acct, currency: currency,
        label: "#{pm.dig('card', 'brand').to_s.upcase} •••• #{pm.dig('card', 'last4')}" }
    else
      { id: pm['id'], type: 'link', brand: 'Link', last4: nil, exp_month: nil, exp_year: nil,
        account: acct, currency: currency,
        label: "Link (#{pm.dig('link', 'email')})" }
    end
  end

  # {a: {b: 1}, c: [..]} -> {"a[b]"=>1, ...} (formato form-encoded de Stripe)
  def self.flatten_params(params, prefix = nil, out = {})
    params.each do |k, v|
      key = prefix ? "#{prefix}[#{k}]" : k.to_s
      case v
      when Hash then flatten_params(v, key, out)
      when Array then v.each_with_index { |item, i| item.is_a?(Hash) ? flatten_params(item, "#{key}[#{i}]", out) : out["#{key}[#{i}]"] = item }
      else out[key] = v
      end
    end
    out
  end

  # Verificacion de firma del webhook (Stripe-Signature: t=..,v1=..)
  def self.verify_webhook(payload, sig_header, secret)
    return false if payload.blank? || sig_header.blank? || secret.blank?
    parts = sig_header.split(',').map { |p| p.split('=', 2) }.to_h
    t = parts['t']
    v1 = parts['v1']
    return false if t.blank? || v1.blank?
    return false if (Time.now.to_i - t.to_i).abs > 300

    expected = OpenSSL::HMAC.hexdigest('sha256', secret, "#{t}.#{payload}")
    ActiveSupport::SecurityUtils.secure_compare(expected, v1)
  rescue StandardError
    false
  end

  # UNA sola URL de webhook para las DOS cuentas: se prueba la firma con el
  # secreto de cada una y gana la que verifique. Devuelve 'us' / 'mx', o nil si
  # ninguna firma cuadra (petición rechazada).
  def self.webhook_account(payload, sig_header)
    ACCOUNTS.detect do |a|
      s = webhook_secret(a)
      s.present? && verify_webhook(payload, sig_header, s)
    end
  end

  # ¿Hay algún secreto de webhook configurado? (si no hay ninguno, el webhook
  # se acepta sin firma, como antes, para no perder pagos durante el alta).
  def self.any_webhook_secret?
    ACCOUNTS.any? { |a| webhook_secret(a).present? }
  end
end
