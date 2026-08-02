# frozen_string_literal: true

module Api
  class WhatsappWebhookController < ApplicationController
    include TokenAuthenticatable
    skip_before_action :authenticate_entity!

    # GET /api/whatsapp/webhook -> handshake de verificacion de Meta
    def verify
      if params['hub.mode'] == 'subscribe' &&
         params['hub.verify_token'].present? &&
         params['hub.verify_token'] == ENV['WHATSAPP_VERIFY_TOKEN']
        render plain: params['hub.challenge'].to_s, status: :ok
      else
        head :forbidden
      end
    end

    # POST /api/whatsapp/webhook -> mensajes entrantes de WhatsApp
    def receive
      return head(:unauthorized) unless valid_signature?

      incoming_messages.each do |msg|
        from = msg['from'].to_s
        body = msg.dig('text', 'body').to_s
        WhatsappVerification.process_incoming(from: from, body: body)
      end
      head :ok
    rescue StandardError => e
      Rails.logger.error "[WhatsappWebhook] #{e.class}: #{e.message}"
      head :ok # responder 200 para que Meta no reintente en bucle
    end

    private

    def incoming_messages
      payload = params.to_unsafe_h
      (payload['entry'] || []).flat_map do |entry|
        (entry['changes'] || []).flat_map { |change| change.dig('value', 'messages') || [] }
      end
    end

    def valid_signature?
      secret = ENV['WHATSAPP_APP_SECRET']
      return true if secret.blank? # sin secret configurado no validamos (modo prueba)
      header = request.headers['X-Hub-Signature-256'].to_s
      return false if header.blank?
      expected = 'sha256=' + OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)
      ActiveSupport::SecurityUtils.secure_compare(header, expected)
    end
  end
end
