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

    # GET /api/whatsapp/threads
    # BANDEJA: TODAS las conversaciones (mensajes + notas de llamada) agrupadas
    # por teléfono — cada persona tiene UNA página de WhatsApp donde cae todo,
    # se envíe desde donde se envíe. Incluye contador de NO LEÍDOS por hilo.
    def threads
      has_read = WhatsappMessage.column_names.include?('read_at')
      groups = {}
      WhatsappMessage.order(:created_at).last(3000).each do |m|
        tail = phone_tail(m.wa_phone)
        next if tail.blank?

        g = groups[tail] ||= { tail: tail, phone: m.wa_phone, unread: 0, last_at: nil,
                               last_preview: nil, last_dir: nil, user_id: m.user_id }
        g[:phone] = m.wa_phone
        g[:user_id] ||= m.user_id
        g[:unread] += 1 if has_read && m.direction == 'in' && m.read_at.nil?
        g[:last_at] = m.created_at
        g[:last_preview] = m.body.to_s[0, 90]
        g[:last_dir] = m.direction
      end
      ContactLog.order(:created_at).last(1500).each do |l|
        tail = phone_tail(l.phone)
        next if tail.blank?

        g = groups[tail] ||= { tail: tail, phone: l.phone, unread: 0, last_at: nil,
                               last_preview: nil, last_dir: nil, user_id: l.user_id }
        g[:user_id] ||= l.user_id
        if g[:last_at].nil? || l.created_at > g[:last_at]
          g[:last_at] = l.created_at
          g[:last_preview] = "📝 #{l.body.to_s[0, 80]}"
          g[:last_dir] = 'note'
        end
      end

      identify_threads!(groups)
      threads = groups.values.sort_by { |g| [-g[:unread], -(g[:last_at]&.to_i || 0)] }
      render json: { threads: threads, unread_threads: threads.count { |t| t[:unread].positive? } }, status: :ok
    end

    # POST /api/whatsapp/read { phone } -> marca el hilo como leído
    def mark_read
      return render(json: { ok: true }, status: :ok) unless WhatsappMessage.column_names.include?('read_at')

      tail = phone_tail(params[:phone])
      return render(json: { error: 'Teléfono inválido' }, status: :unprocessable_entity) if tail.blank?

      WhatsappMessage.where(direction: 'in', read_at: nil)
                     .where("regexp_replace(coalesce(wa_phone,''), '[^0-9]', '', 'g') LIKE ?", "%#{tail}")
                     .update_all(read_at: Time.current)
      render json: { ok: true }, status: :ok
    end

    # DELETE /api/whatsapp/messages/:id  (SOLO master/admin)
    # Borra el mensaje de NUESTRO registro. OJO: no se puede borrar del teléfono
    # del cliente (WhatsApp no lo permite por API). Queda en la bitácora.
    def destroy
      unless %w[master admin].include?(@current_user&.role&.name)
        return render json: { error: 'Solo master o admin pueden eliminar mensajes' }, status: :forbidden
      end
      m = WhatsappMessage.find(params[:id])
      excerpt = m.body.to_s[0, 80]
      phone = m.wa_phone
      m.destroy!
      AuditLog.record!(actor: @current_user, action: 'wa_message_deleted',
                       label: phone.to_s, details: "#{m.direction == 'in' ? 'Recibido' : 'Enviado'}: “#{excerpt}”")
      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Mensaje no encontrado' }, status: :not_found
    end

    # GET /api/whatsapp/unread_count -> hilos con mensajes nuevos (globo del menú)
    def unread_count
      unless WhatsappMessage.column_names.include?('read_at')
        return render(json: { unread_threads: 0 }, status: :ok)
      end
      phones = WhatsappMessage.where(direction: 'in', read_at: nil).pluck(:wa_phone)
      render json: { unread_threads: phones.map { |p| phone_tail(p) }.reject(&:blank?).uniq.size }, status: :ok
    end

    private

    # Identificar a la persona de cada hilo por teléfono: cliente > comprador >
    # beneficiario > referencia; más su contrato reciente y carrito (CRM).
    def identify_threads!(groups)
      return if groups.empty?

      users = User.where.not(phone: [nil, '']).includes(:role).to_a
      by_user_id = User.where(id: groups.values.filter_map { |g| g[:user_id] }).includes(:role).index_by(&:id)
      carts = begin
        defined?(CartSnapshot) && CartSnapshot.table_exists? ? CartSnapshot.pluck(:user_id) : []
      rescue StandardError
        []
      end
      buyers = Buyer.where.not(phone: [nil, '']).to_a
      bens = Beneficiary.where.not(phone: [nil, '']).to_a
      refs = Referral.where.not(phone: [nil, '']).to_a
      labels = { 'cliente' => 'Cliente', 'comprador' => 'Comprador', 'beneficiario' => 'Beneficiario',
                 'referencia' => 'Referencia', 'equipo' => 'Equipo' }

      groups.each_value do |g|
        u = by_user_id[g[:user_id]] || users.find { |x| phone_tail(x.phone) == g[:tail] }
        if u
          g[:person_type] = u.role&.name == 'cliente' ? 'cliente' : 'equipo'
          g[:name] = [u.name, u.last_name].compact.join(' ').strip.presence || u.email
          g[:user_id] ||= u.id
        elsif (b = buyers.find { |x| phone_tail(x.phone) == g[:tail] })
          g[:person_type] = 'comprador'
          g[:name] = [b.name, b.last_name].compact.join(' ').strip
          g[:user_id] ||= b.order&.user_id
        elsif (bn = bens.find { |x| phone_tail(x.phone) == g[:tail] })
          g[:person_type] = 'beneficiario'
          g[:name] = [bn.name, bn.last_name].compact.join(' ').strip
          g[:user_id] ||= bn.user_id
        elsif (rf = refs.find { |x| phone_tail(x.phone) == g[:tail] })
          g[:person_type] = 'referencia'
          g[:name] = [rf.name, rf.last_name].compact.join(' ').strip
        end
        g[:person_label] = labels[g[:person_type]]
        next unless g[:user_id]

        g[:has_cart] = carts.include?(g[:user_id])
        c = Contract.where(user_id: g[:user_id]).order(id: :desc).first
        if c
          g[:contract_id] = c.id
          g[:contract_number] = c.contract_number.presence || (c.respond_to?(:order_ref) ? c.order_ref : nil)
        end
      end
    end

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
