# frozen_string_literal: true

module Api
  # SOPORTE con tickets (página "Soporte" bajo la línea): registrar por cliente,
  # dar seguimiento con notas y llevarlo hasta su RESOLUCIÓN. Todo a la Bitácora.
  class SupportTicketsController < ApplicationController
    include TokenAuthenticatable

    ROLES = %w[master admin sistema editor operador gerente admin_cuentas admin_redes].freeze
    before_action :authorize_staff!
    before_action :ensure_table!

    # GET /api/support/tickets?status=&q=
    def index
      scope = SupportTicket.order(Arel.sql("CASE status WHEN 'abierto' THEN 0 WHEN 'en_proceso' THEN 1 WHEN 'esperando_cliente' THEN 2 ELSE 3 END"),
                                  Arel.sql("CASE priority WHEN 'alta' THEN 0 WHEN 'media' THEN 1 ELSE 2 END"),
                                  updated_at: :desc)
      scope = scope.where(status: params[:status]) if SupportTicket::STATUSES.include?(params[:status].to_s)
      if params[:q].present?
        q = "%#{params[:q].to_s.strip}%"
        scope = scope.where('customer_name ILIKE :q OR subject ILIKE :q OR phone ILIKE :q OR description ILIKE :q', q: q)
      end
      counts = SupportTicket.group(:status).count
      render json: { tickets: scope.limit(300).map { |t| serialize(t) }, counts: counts }, status: :ok
    end

    # GET /api/support/tickets/:id
    def show
      t = SupportTicket.find(params[:id])
      render json: { ticket: serialize(t, notes: true) }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Ticket no encontrado' }, status: :not_found
    end

    # POST /api/support/tickets { user_id?, customer_name, phone, subject, description, priority, channel }
    def create
      user = params[:user_id].present? ? User.find_by(id: params[:user_id]) : nil
      user ||= match_user_by_phone(params[:phone])
      name = params[:customer_name].to_s.strip.presence ||
             (user ? [user.name, user.last_name].compact.join(' ').strip : nil)
      return render(json: { error: 'Indica el cliente (nombre o teléfono)' }, status: :unprocessable_entity) if name.blank?

      t = SupportTicket.create!(
        user_id: user&.id, customer_name: name,
        phone: params[:phone].to_s.gsub(/\D/, '').presence || user&.phone.to_s.gsub(/\D/, '').presence,
        subject: params[:subject].to_s.strip, description: params[:description].to_s.strip,
        priority: (SupportTicket::PRIORITIES.include?(params[:priority].to_s) ? params[:priority] : 'media'),
        channel: params[:channel].presence || 'admin',
        created_by: staff_name
      )
      AuditLog.record!(actor: @current_user, action: 'ticket_created', target: t, label: t.ref,
                       details: "#{t.customer_name} · #{t.subject[0, 120]}")
      render json: { ok: true, ticket: serialize(t, notes: true) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(' · ') }, status: :unprocessable_entity
    end

    # PUT /api/support/tickets/:id { status?, priority?, assigned_name?, resolution?, subject?, description? }
    def update
      t = SupportTicket.find(params[:id])
      fields = {}
      if params.key?(:status)
        st = params[:status].to_s
        return render(json: { error: 'Estado inválido' }, status: :unprocessable_entity) unless SupportTicket::STATUSES.include?(st)

        if st == 'resuelto'
          res = params[:resolution].to_s.strip.presence || t.resolution.to_s.strip.presence
          return render(json: { error: 'Escribe CÓMO se resolvió antes de cerrar el ticket' }, status: :unprocessable_entity) if res.blank?

          fields[:resolution] = res
          fields[:resolved_at] = Time.current
        else
          fields[:resolved_at] = nil # reabrir
        end
        fields[:status] = st
      end
      fields[:priority] = params[:priority] if SupportTicket::PRIORITIES.include?(params[:priority].to_s)
      fields[:assigned_name] = params[:assigned_name].to_s.strip[0, 80] if params.key?(:assigned_name)
      fields[:resolution] = params[:resolution].to_s.strip if params.key?(:resolution) && !fields.key?(:resolution)
      fields[:subject] = params[:subject].to_s.strip if params[:subject].present?
      fields[:description] = params[:description].to_s if params.key?(:description)
      t.update!(fields) if fields.any?

      if fields[:status] == 'resuelto'
        t.notes.create!(author_name: staff_name, body: "✅ RESUELTO: #{t.resolution.to_s[0, 400]}")
        AuditLog.record!(actor: @current_user, action: 'ticket_resolved', target: t, label: t.ref,
                         details: "#{t.customer_name} · #{t.resolution.to_s[0, 150]}")
        notify_resolved(t)
      elsif fields.any?
        AuditLog.record!(actor: @current_user, action: 'ticket_updated', target: t, label: t.ref,
                         details: fields.keys.join(', '))
      end
      render json: { ok: true, ticket: serialize(t.reload, notes: true) }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Ticket no encontrado' }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(' · ') }, status: :unprocessable_entity
    end

    # POST /api/support/tickets/:id/notes { body }
    def create_note
      t = SupportTicket.find(params[:id])
      body = params[:body].to_s.strip
      return render(json: { error: 'Escribe la nota' }, status: :unprocessable_entity) if body.blank?

      t.notes.create!(author_name: staff_name, body: body)
      t.touch
      render json: { ok: true, ticket: serialize(t.reload, notes: true) }, status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Ticket no encontrado' }, status: :not_found
    end

    private

    # ✅ Al RESOLVER: aviso automático por WhatsApp al cliente con la resolución.
    # Texto EDITABLE en Respuestas WhatsApp ('soporte_resuelto'). Si su ventana
    # de 24 h está cerrada y no hay plantilla, queda anotado en el ticket.
    def notify_resolved(t)
      return if t.phone.to_s.strip.blank?

      nombre = t.customer_name.to_s.split.first.presence || 'hola'
      texto = WaAutoText.render('soporte_resuelto', nombre: nombre, ticket: t.ref,
                                resolucion: t.resolution.to_s[0, 300])
      r = WhatsappOutbound.deliver(phone: t.phone, text: texto, user: t.user, actor: @current_user)
      t.notes.create!(author_name: 'Automático',
                      body: r[:ok] ? '📲 Aviso de resolución enviado al cliente por WhatsApp' : "⚠ No se pudo avisar por WhatsApp: #{r[:error]}")
    rescue StandardError => e
      Rails.logger.warn "[SupportTickets] notify_resolved: #{e.message}"
    end

    def serialize(t, notes: false)
      h = { id: t.id, ref: t.ref, user_id: t.user_id, customer_name: t.customer_name,
            phone: t.phone, subject: t.subject, description: t.description,
            channel: t.channel, status: t.status, priority: t.priority,
            assigned_name: t.assigned_name, resolution: t.resolution,
            resolved_at: t.resolved_at, created_by: t.created_by,
            created_at: t.created_at, updated_at: t.updated_at }
      h[:notes] = t.notes.order(:created_at).map { |n| { author: n.author_name, body: n.body, at: n.created_at } } if notes
      h
    end

    def staff_name
      [@current_user&.name, @current_user&.last_name].compact.join(' ').strip.presence || @current_user&.email.to_s
    end

    def match_user_by_phone(phone)
      User.by_whatsapp_tail(phone) # siempre la cuenta VERIFICADA del número
    end

    def ensure_table!
      return if SupportTicket.table_exists?

      render json: { error: 'Falta la migración de soporte (bin/rails db:migrate)' }, status: :unprocessable_entity
    end

    def authorize_staff!
      return if ROLES.include?(@current_user&.role&.name)

      render json: { error: 'No autorizado' }, status: :forbidden
    end
  end
end
