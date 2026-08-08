# frozen_string_literal: true

module Api
  # Bitácora de conversaciones por persona (solo staff).
  # GET  /api/contact_logs?phone=...            -> notas de esa persona (por teléfono)
  # GET  /api/contact_logs?user_id=...          -> notas ligadas a la cuenta del cliente
  # POST /api/contact_logs { user_id, order_id, person_type, person_name, phone, body }
  class ContactLogsController < ApplicationController
    include TokenAuthenticatable

    before_action :authorize_staff!

    def index
      logs = ContactLog.all
      if params[:phone].present?
        logs = logs.for_phone(params[:phone])
      elsif params[:user_id].present?
        logs = logs.where(user_id: params[:user_id])
        logs = logs.where(person_type: params[:person_type]) if params[:person_type].present?
      else
        return render json: { error: 'Falta phone o user_id' }, status: :bad_request
      end
      render json: { logs: logs.order(:created_at).last(300).map { |l| serialize(l) } }, status: :ok
    end

    def create
      body = params[:body].to_s.strip
      return render(json: { error: 'Escribe la nota' }, status: :unprocessable_entity) if body.blank?

      log = ContactLog.create!(
        user_id: params[:user_id].presence,
        order_id: params[:order_id].presence,
        person_type: params[:person_type].to_s.presence,
        person_name: params[:person_name].to_s.presence,
        phone: params[:phone].to_s.gsub(/\D/, '').presence,
        body: body,
        author_id: @current_user&.id,
        author_name: [@current_user&.name, @current_user&.last_name].compact.join(' ').presence || @current_user&.email
      )
      render json: { ok: true, log: serialize(log) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

    # POST /api/contact_logs/email  { user_id, email, name, subject, body, phone, person_type }
    # Envía un CORREO al cliente desde el CRM/cobranza y lo deja registrado en su
    # bitácora, igual que una llamada o un WhatsApp.
    def email
      to = params[:email].to_s.strip
      body = params[:body].to_s.strip
      subject = params[:subject].to_s.strip
      to = User.find_by(id: params[:user_id])&.email if to.blank? && params[:user_id].present?
      return render(json: { error: 'Falta el correo del destinatario' }, status: :unprocessable_entity) if to.blank?
      return render(json: { error: 'Escribe el mensaje' }, status: :unprocessable_entity) if body.blank?

      from_name = [@current_user&.name, @current_user&.last_name].compact.join(' ').strip.presence || 'Equipo Ácasa'
      begin
        UserMailer.with(to: to, name: params[:name].to_s.presence, body: body,
                        subject: subject.presence, from_name: from_name).send_staff_message.deliver_now
      rescue StandardError => e
        return render(json: { error: "No se pudo enviar el correo: #{e.message}" }, status: :unprocessable_entity)
      end

      log = ContactLog.create!(
        user_id: params[:user_id].presence,
        person_type: params[:person_type].to_s.presence || 'customer',
        person_name: params[:name].to_s.presence,
        phone: params[:phone].to_s.gsub(/\D/, '').presence,
        body: "📧 CORREO a #{to}#{subject.present? ? " · #{subject}" : ''}\n#{body}",
        author_id: @current_user&.id,
        author_name: from_name
      )
      render json: { ok: true, log: serialize(log) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

    # DELETE /api/contact_logs/:id  (SOLO master/admin) — queda en la bitácora.
    def destroy
      unless %w[master admin].include?(@current_user&.role&.name)
        return render json: { error: 'Solo master o admin pueden eliminar notas' }, status: :forbidden
      end
      l = ContactLog.find(params[:id])
      excerpt = l.body.to_s[0, 80]
      l.destroy!
      AuditLog.record!(actor: @current_user, action: 'note_deleted',
                       label: (l.person_name.presence || l.phone.to_s), details: "“#{excerpt}”")
      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Nota no encontrada' }, status: :not_found
    end

    private

    def serialize(l)
      { id: l.id, user_id: l.user_id, order_id: l.order_id, person_type: l.person_type,
        person_name: l.person_name, phone: l.phone, body: l.body,
        author_name: l.author_name, created_at: l.created_at }
    end

    def authorize_staff!
      return if %w[master admin sistema editor operador gerente admin_cuentas admin_redes].include?(@current_user&.role&.name)
      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
