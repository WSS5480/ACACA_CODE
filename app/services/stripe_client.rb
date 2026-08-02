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
