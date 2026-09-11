# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module BankFeeds
  # Cliente mínimo para la API de Plaid (bancos de EE. UU.), sin gema — igual que
  # StripeClient. Variables de entorno (Render):
  #   PLAID_CLIENT_ID, PLAID_SECRET  → del dashboard de Plaid (Team Settings → Keys)
  #   PLAID_ENV                      → sandbox | production   (default: sandbox)
  # El equipo NUNCA captura credenciales bancarias aquí: la persona las escribe en
  # la ventana de Plaid Link (en su navegador) y nosotros solo recibimos un token.
  class PlaidClient
    HOSTS = { 'sandbox' => 'https://sandbox.plaid.com', 'production' => 'https://production.plaid.com' }.freeze
    PLAID_VERSION = '2020-09-14'
    DAYS_REQUESTED = 365 # historial que se pide al conectar (máx. 730)

    class Error < StandardError
      attr_reader :code, :type, :http

      def initialize(message, code: nil, type: nil, http: nil)
        super(message)
        @code = code
        @type = type
        @http = http
      end

      def login_required?  = code == 'ITEM_LOGIN_REQUIRED'
      def rate_limited?    = type == 'RATE_LIMIT_EXCEEDED'
      def mutation_during_pagination? = code == 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION'
    end

    def self.env
      e = ENV['PLAID_ENV'].to_s.strip.downcase
      HOSTS.key?(e) ? e : 'sandbox'
    end

    def self.configured?
      ENV['PLAID_CLIENT_ID'].present? && ENV['PLAID_SECRET'].present?
    end

    def self.post(path, body = {})
      raise Error, 'Plaid no está configurado (PLAID_CLIENT_ID / PLAID_SECRET en Render)' unless configured?

      uri = URI("#{HOSTS.fetch(env)}#{path}")
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req['Plaid-Version'] = PLAID_VERSION
      req['PLAID-CLIENT-ID'] = ENV['PLAID_CLIENT_ID']
      req['PLAID-SECRET'] = ENV['PLAID_SECRET']
      req.body = JSON.generate(body)
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(req) }
      data = begin
        JSON.parse(res.body)
      rescue StandardError
        {}
      end
      unless res.is_a?(Net::HTTPSuccess)
        raise Error.new(data['display_message'].presence || data['error_message'].presence || "Plaid HTTP #{res.code}",
                        code: data['error_code'], type: data['error_type'], http: res.code.to_i)
      end
      data
    end

    # Token para abrir Plaid Link. Con access_token = MODO ACTUALIZACIÓN (re-login
    # de una conexión existente); sin él = conexión nueva.
    def self.link_token(client_user_id:, webhook:, redirect_uri:, access_token: nil)
      body = {
        client_name: 'acasa', language: 'es', country_codes: ['US'],
        user: { client_user_id: client_user_id.to_s },
        webhook: webhook
      }
      body[:redirect_uri] = redirect_uri if redirect_uri.present?
      if access_token.present?
        body[:access_token] = access_token
        body[:update] = { account_selection_enabled: true }
      else
        body[:products] = ['transactions']
        body[:transactions] = { days_requested: DAYS_REQUESTED }
      end
      post('/link/token/create', body)
    end

    def self.exchange(public_token)
      post('/item/public_token/exchange', { public_token: public_token })
    end

    def self.accounts(access_token)
      post('/accounts/get', { access_token: access_token })
    end

    def self.item(access_token)
      post('/item/get', { access_token: access_token })
    end

    def self.institution(institution_id)
      return nil if institution_id.blank?

      post('/institutions/get_by_id', { institution_id: institution_id, country_codes: ['US'] })['institution']
    rescue Error
      nil
    end

    # Una página de /transactions/sync. El que llama itera mientras has_more.
    def self.sync(access_token, cursor, count: 500)
      body = { access_token: access_token, count: count,
               options: { include_original_description: true, days_requested: DAYS_REQUESTED } }
      body[:cursor] = cursor if cursor.present?
      post('/transactions/sync', body)
    end

    def self.remove(access_token)
      post('/item/remove', { access_token: access_token })
    end
  end
end
