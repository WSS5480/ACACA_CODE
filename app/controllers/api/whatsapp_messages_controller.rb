# frozen_string_literal: true

module Api
  class WhatsappMessagesController < ApplicationController
    include TokenAuthenticatable

    before_action :authorize_staff!

    # GET /api/whatsapp/messages?user_id=
    def index
      user = User.find_by(id: params[:user_id])
      return render(json: { error: 'Cliente no encontrado' }, status: :not_found) unless user

      msgs = WhatsappMessage.for_user(user.id).last(200).map do |m|
        { id: m.id, direction: m.direction, body: m.body, media_type: m.media_type,
          media_url: m.media_url, created_at: m.created_at }
      end
      render json: { phone: user.phone, messages: msgs }, status: :ok
    end

    # POST /api/whatsapp/send { user_id, message }
    def create
      user = User.find_by(id: params[:user_id])
      return render(json: { error: 'Cliente no encontrado' }, status: :not_found) unless user
      return render(json: { error: 'El cliente no tiene teléfono registrado' }, status: :unprocessable_entity) if user.phone.blank?

      body = params[:message].to_s.strip
      return render(json: { error: 'Escribe un mensaje' }, status: :unprocessable_entity) if body.blank?

      begin
        WhatsappCloud.new.send_text(user.phone, body)
      rescue WhatsappCloud::NotConfigured
        return render(json: { error: 'WhatsApp no está configurado en el servidor' }, status: :unprocessable_entity)
      rescue WhatsappCloud::DeliveryError => e
        hint = e.message.to_s =~ /24|window|re-engagement/i ? ' (El cliente debe escribirnos primero: fuera de la ventana de 24 horas se requiere una plantilla aprobada.)' : ''
        return render(json: { error: "No se pudo enviar: #{e.message}#{hint}" }, status: :unprocessable_entity)
      end

      m = WhatsappMessage.create!(user: user, direction: 'out', wa_phone: WhatsappCloud.normalize_phone(user.phone),
                                  body: body, sent_by_id: @current_user.id)
      render json: { ok: true, message: { id: m.id, direction: 'out', body: m.body, created_at: m.created_at } }, status: :created
    end

    private

    def authorize_staff!
      return if %w[master admin].include?(@current_user&.role&.name)
      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
