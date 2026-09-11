# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

# Cliente minimo para la API REST de Stripe (sin gema).
# Usa STRIPE_SECRET_KEY del entorno. Todos los montos en CENTAVOS de USD.
class StripeClient
  BASE = 'https://api.stripe.com'

  class Error < StandardError; end

  def self.configured?
    ENV['STRIPE_SECRET_KEY'].present?
  end

  def self.request(method, path, params = nil)
    raise Error, 'Stripe no esta configurado (STRIPE_SECRET_KEY)' unless configured?

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
    req['Authorization'] = "Bearer #{ENV['STRIPE_SECRET_KEY']}"
    req['Stripe-Version'] = '2024-06-20'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
    body = JSON.parse(res.body) rescue {}
    unless res.is_a?(Net::HTTPSuccess)
      msg = body.dig('error', 'message') || "Stripe HTTP #{res.code}"
      raise Error, msg
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

  def self.saved_methods(customer_id)
    return [] if customer_id.blank?

    res = request(:get, '/v1/payment_methods', { customer: customer_id, limit: 100 })
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
        seen[key] = normalize_method(pm)
      end
    end
    dupes.each do |id|
      request(:post, "/v1/payment_methods/#{id}/detach", {})
    rescue Error
      nil # si no se pudo desprender, igual queda fuera de la lista
    end
    seen.values
  end

  def self.normalize_method(pm)
    if pm['type'] == 'card'
      { id: pm['id'], type: 'card', brand: pm.dig('card', 'brand'), last4: pm.dig('card', 'last4'),
        exp_month: pm.dig('card', 'exp_month'), exp_year: pm.dig('card', 'exp_year'),
        label: "#{pm.dig('card', 'brand').to_s.upcase} •••• #{pm.dig('card', 'last4')}" }
    else
      { id: pm['id'], type: 'link', brand: 'Link', last4: nil, exp_month: nil, exp_year: nil,
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
end
