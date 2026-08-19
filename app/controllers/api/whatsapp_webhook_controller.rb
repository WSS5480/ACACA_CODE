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
        archive_message(msg, from, body)
        # Respuesta de BOTÓN de la mini-entrevista -> avanza la encuesta;
        # cualquier otro mensaje de una referencia pendiente -> la inicia.
        bid = msg.dig('interactive', 'button_reply', 'id').to_s
        handled = bid.present? && defined?(ReferenceSurvey) &&
                  ReferenceSurvey.handle_button(from: from, id: bid,
                                                title: msg.dig('interactive', 'button_reply', 'title').to_s)
        ReferenceSurvey.on_inbound(from) if !handled && defined?(ReferenceSurvey)
      end
      incoming_statuses.each { |st| apply_status(st) }
      head :ok
    rescue StandardError => e
      Rails.logger.error "[WhatsappWebhook] #{e.class}: #{e.message}"
      head :ok # responder 200 para que Meta no reintente en bucle
    end

    private

    # Archiva TODO mensaje entrante (texto y fotos/documentos) en el expediente del cliente.
    def archive_message(msg, from, body)
      return if msg['id'].present? && WhatsappMessage.exists?(wa_message_id: msg['id'])

      user = match_user(from)
      mtype = msg['type'].to_s
      caption = body.presence
      media_id = nil
      if %w[image document video audio sticker].include?(mtype)
        media_id = msg.dig(mtype, 'id')
        caption ||= msg.dig(mtype, 'caption').to_s.presence || msg.dig(mtype, 'filename').to_s.presence
      end
      # Respuesta de botón interactivo: archivar el TÍTULO del botón elegido.
      if mtype == 'interactive'
        caption ||= msg.dig('interactive', 'button_reply', 'title').to_s.presence ||
                    msg.dig('interactive', 'list_reply', 'title').to_s.presence
      end

      record = WhatsappMessage.create!(
        user: user, direction: 'in', wa_phone: from,
        body: caption, media_type: (media_id ? mtype : nil), wa_message_id: msg['id']
      )

      if media_id && WhatsappCloud.configured?
        data = WhatsappCloud.new.download_media(media_id)
        if data
          bin, mime, fname = data
          record.media.attach(io: StringIO.new(bin), filename: fname, content_type: mime)
        end
      end
    rescue StandardError => e
      Rails.logger.error "[WhatsappWebhook] archive: #{e.class}: #{e.message}"
    end

    def match_user(from)
      tail = from.to_s.gsub(/[^0-9]/, '')[-10..]
      return nil if tail.blank?
      User.where.not(phone: [nil, '']).find { |u| u.phone.to_s.gsub(/[^0-9]/, '')[-10..] == tail }
    end

    def incoming_messages
      payload = params.to_unsafe_h
      (payload['entry'] || []).flat_map do |entry|
        (entry['changes'] || []).flat_map { |change| change.dig('value', 'messages') || [] }
      end
    end

    # Recibos de entrega de Meta ('statuses'): sent -> delivered -> read | failed.
    def incoming_statuses
      payload = params.to_unsafe_h
      (payload['entry'] || []).flat_map do |entry|
        (entry['changes'] || []).flat_map { |change| change.dig('value', 'statuses') || [] }
      end
    end

    # Actualiza las "palomitas" del mensaje saliente. Solo avanza (nunca regresa
    # de leído a entregado) y es inofensivo si la migración aún no corre.
    STATUS_ORDER = { 'sent' => 1, 'delivered' => 2, 'read' => 3, 'failed' => 9 }.freeze
    def apply_status(st)
      return unless WhatsappMessage.column_names.include?('status')

      rec = WhatsappMessage.find_by(wa_message_id: st['id'].to_s)
      return unless rec

      new_s = st['status'].to_s
      return unless STATUS_ORDER.key?(new_s)
      return if (STATUS_ORDER[new_s] || 0) <= (STATUS_ORDER[rec.status.to_s] || 0)

      at = begin
        Time.zone.at(st['timestamp'].to_i)
      rescue StandardError
        Time.current
      end
      cols = { status: new_s, status_at: at }
      if new_s == 'failed'
        err = Array(st['errors']).first || {}
        reason = [err['code'], err['title'] || err['message'], err.dig('error_data', 'details')].compact.join(' · ')
        Rails.logger.warn "[WhatsappWebhook] mensaje NO entregado (#{rec.wa_phone}): #{reason}"
        cols[:status_error] = reason.to_s[0, 250] if WhatsappMessage.column_names.include?('status_error')
      end
      rec.update_columns(cols)
    rescue StandardError => e
      Rails.logger.warn "[WhatsappWebhook] status: #{e.message}"
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
