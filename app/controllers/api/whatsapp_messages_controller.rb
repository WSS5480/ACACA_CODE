# frozen_string_literal: true

module Api
  class WhatsappMessagesController < ApplicationController
    include TokenAuthenticatable

    before_action :authorize_staff!

    # GET /api/whatsapp/messages?user_id=   -> hilo del cliente (cuenta)
    # GET /api/whatsapp/messages?phone=     -> hilo por teléfono (comprador, beneficiario, referencia)
    def index
      if params[:phone].present?
        tail = phone_tail(params[:phone])
        return render(json: { error: 'Teléfono inválido' }, status: :unprocessable_entity) if tail.blank?

        scope = WhatsappMessage.where("regexp_replace(coalesce(wa_phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{tail}").order(:created_at)
        render json: { phone: params[:phone], messages: scope.last(200).map { |m| serialize(m) } }, status: :ok
      else
        user = User.find_by(id: params[:user_id])
        return render(json: { error: 'Cliente no encontrado' }, status: :not_found) unless user

        msgs = WhatsappMessage.for_user(user.id).last(200).map { |m| serialize(m) }
        render json: { phone: user.phone, messages: msgs }, status: :ok
      end
    end

    # POST /api/whatsapp/send { user_id, message }          -> al teléfono del cliente
    # POST /api/whatsapp/send { phone, message, user_id? }  -> a un teléfono específico (comprador/beneficiario/referencia)
    def create
      body = params[:message].to_s.strip
      return render(json: { error: 'Escribe un mensaje' }, status: :unprocessable_entity) if body.blank?

      user = params[:user_id].present? ? User.find_by(id: params[:user_id]) : nil
      phone = params[:phone].presence || user&.phone
      if phone.blank?
        return render(json: { error: user ? 'El cliente no tiene teléfono registrado' : 'Falta el teléfono' }, status: :unprocessable_entity)
      end

      # Si no vino user_id, intentar ligar el mensaje a la cuenta por el teléfono.
      user ||= match_user_by_phone(phone)

      begin
        WhatsappCloud.new.send_text(phone, body)
      rescue WhatsappCloud::NotConfigured
        return render(json: { error: 'WhatsApp no está configurado en el servidor' }, status: :unprocessable_entity)
      rescue WhatsappCloud::DeliveryError => e
        hint = e.message.to_s =~ /24|window|re-engagement/i ? ' (La persona debe escribirnos primero: fuera de la ventana de 24 horas se requiere una plantilla aprobada.)' : ''
        return render(json: { error: "No se pudo enviar: #{e.message}#{hint}" }, status: :unprocessable_entity)
      end

      m = WhatsappMessage.create!(user: user, direction: 'out', wa_phone: WhatsappCloud.normalize_phone(phone),
                                  body: body, sent_by_id: @current_user.id)
      render json: { ok: true, message: serialize(m) }, status: :created
    end

    private

    def serialize(m)
      { id: m.id, direction: m.direction, body: m.body, media_type: m.media_type,
        media_url: m.media_url, created_at: m.created_at }
    end

    def phone_tail(raw)
      d = raw.to_s.gsub(/\D/, '')
      d.length > 10 ? d[-10..] : d
    end

    def match_user_by_phone(raw)
      tail = phone_tail(raw)
      return nil if tail.blank?
      User.where.not(phone: [nil, '']).find { |u| phone_tail(u.phone) == tail }
    end

    def authorize_staff!
      return if %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(@current_user&.role&.name)
      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
