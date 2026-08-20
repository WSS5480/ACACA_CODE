# frozen_string_literal: true

# VERIFICACIÓN AUTOMÁTICA de referencias por WhatsApp.
# Al completarse los datos de una compra (comprador + 4 referencias) se encolan:
#   ref_personal  -> teléfono personal de cada referencia
#   ref_trabajo   -> teléfono de trabajo de cada referencia (si lo dio)
#   ref_domicilio -> contacto del domicilio del comprador (casero/conocido)
# Un job cada 15 minutos envía las pendientes SOLO en horario local 8am–9pm:
#   México:  10:00–18:59 hora del Centro  -> 8am–9pm en TODOS los husos de MX
#   EE.UU.:  12:00–20:59 hora del Este    -> 8am–9pm del Este al de Alaska
# Cada plantilla se envía únicamente cuando Meta ya la APROBÓ (si sigue en
# revisión, el envío espera solo y se reintenta en el siguiente ciclo).
class ReferencePing < ApplicationRecord
  belongs_to :contract, optional: true

  TPL = { 'personal' => 'ref_personal', 'trabajo' => 'ref_trabajo', 'domicilio' => 'ref_domicilio' }.freeze

  scope :pending, -> { where(status: 'pending') }

  # Encola (con dedupe) todo lo verificable de un contrato con datos completos.
  def self.enqueue_for!(contract)
    return unless table_exists? && contract
    return unless contract.respond_to?(:datos_complete?) && contract.datos_complete?

    cust = [contract.user&.name, contract.user&.last_name].compact.join(' ').strip.presence || 'nuestro cliente'
    order = contract.orders.detect { |o| o.respond_to?(:referrals) && o.referrals.any? } || contract.orders.first
    return unless order

    order.referrals.each do |rf|
      rname = [rf.name, rf.last_name].compact.join(' ').strip
      add!(contract, 'personal', rf.phone, rname, cust)
      add!(contract, 'trabajo', rf.respond_to?(:phone_work) ? rf.phone_work : nil, rname, cust)
    end
    b = order.respond_to?(:buyer) ? order.buyer : nil
    if b && b.respond_to?(:home_contact_phone)
      add!(contract, 'domicilio', b.home_contact_phone, b.home_contact_name, cust)
    end
    # EMPLEO: el teléfono del trabajo del COMPRADOR también recibe verificación
    # (saludo neutro "buen día" porque no capturamos nombre de contacto ahí).
    if b && b.respond_to?(:phone_work) && b.phone_work.present?
      add!(contract, 'trabajo', b.phone_work, 'buen día', cust)
    end
    send_forward_pack!(contract)
  rescue StandardError => e
    Rails.logger.error "[ReferencePing] enqueue: #{e.message}"
  end

  # 📨 PAQUETE DE REENVÍO: además de los mensajes directos, AL CLIENTE se le
  # manda un mensaje listo para REENVIAR a cada contacto (referencias, contacto
  # de domicilio y trabajo). El contacto solo toca el enlace de WhatsApp con
  # texto precargado y nos escribe — su ventana de 24 h se abre y la
  # verificación se hace en conversación libre, sin esperar plantillas.
  # Se envía UNA sola vez por contrato (marcador en el historial).
  def self.send_forward_pack!(contract)
    user = contract&.user
    return if user&.phone.to_s.strip.blank?

    ref = contract.respond_to?(:order_ref) ? contract.order_ref : "PED-#{contract.id}"
    marker = "🤖 Paquete de reenvío (#{ref})"
    # Dedupe POR CONTACTO: si el cliente ACTUALIZA una referencia (teléfono
    # nuevo) después del primer paquete, solo el contacto NUEVO recibe su
    # mensaje de reenvío — los ya enviados no se repiten.
    prior_logs = ContactLog.where(user_id: user.id).where('body LIKE ?', "%#{marker}%").pluck(:body)
    first_pack = prior_logs.empty?
    sent_tails = prior_logs.flat_map { |t| t.scan(/\[(\d{10})\]/).flatten }

    cust = [user.name, user.last_name].compact.join(' ').strip.presence || 'cliente Ácasa'
    order = contract.orders.detect { |o| o.respond_to?(:referrals) && o.referrals.any? } || contract.orders.first
    return unless order

    tailof = ->(p) { d = p.to_s.gsub(/\D/, ''); d.length >= 10 ? d[-10..] : nil }
    link = 'https://www.acasamx.com/wa' # enlace corto y humano: abre nuestro WhatsApp
    # Textos EDITABLES en Configuración → Respuestas WhatsApp.
    msgs = [] # [texto, tail]
    order.referrals.each do |rf|
      t = tailof.call(rf.phone)
      next if t.blank? || sent_tails.include?(t)

      rname = [rf.name, rf.last_name].compact.join(' ').strip.presence || 'amig@'
      msgs << [WaAutoText.render('fwd_referencia', referencia: rname.split.first, cliente: cust, enlace: link), t]
    end
    b = order.respond_to?(:buyer) ? order.buyer : nil
    if b && b.respond_to?(:home_contact_phone) && b.home_contact_phone.present?
      t = tailof.call(b.home_contact_phone)
      if t.present? && !sent_tails.include?(t)
        hname = b.home_contact_name.to_s.strip.presence || 'hola'
        msgs << [WaAutoText.render('fwd_domicilio', referencia: hname.split.first, cliente: cust, enlace: link), t]
      end
    end
    if b && b.respond_to?(:phone_work) && b.phone_work.present?
      t = tailof.call(b.phone_work)
      msgs << [WaAutoText.render('fwd_trabajo', cliente: cust, enlace: link), t] if t.present? && !sent_tails.include?(t)
    end
    return if msgs.empty?

    intro = first_pack ? WaAutoText.render('fwd_intro', nombre: user.name.to_s.split.first) : nil
    ok = 0
    ok_tails = []
    ([intro].compact.map { |x| [x, nil] } + msgs).each do |(t, tail)|
      r = WhatsappOutbound.deliver(phone: user.phone, text: t, user: user)
      break unless r[:ok] # ventana cerrada: no insistir (se reintenta al próximo guardado de datos)

      ok += 1
      ok_tails << tail if tail
    end
    if ok.positive? && ok_tails.any?
      ContactLog.create!(user_id: user.id, person_type: 'buyer', person_name: cust, phone: user.phone,
                         author_name: 'Automático',
                         body: "#{marker}: #{ok} mensaje(s) al cliente para reenviar " \
                               "#{first_pack ? 'a sus referencias, domicilio y trabajo' : '(contactos NUEVOS o actualizados)'} " \
                               "#{ok_tails.map { |t| "[#{t}]" }.join(' ')}")
    end
  rescue StandardError => e
    Rails.logger.error "[ReferencePing] forward_pack: #{e.message}"
    WaAlert.notify('Paquete de reenvío al cliente', e.message) if defined?(WaAlert)
  end


  def self.add!(contract, kind, phone, name, cust)
    digits = phone.to_s.gsub(/\D/, '')
    return if digits.length < 10

    create_with(ref_name: name.to_s.strip.presence || 'contacto', customer_name: cust, status: 'pending')
      .find_or_create_by!(contract_id: contract.id, target_kind: kind, phone: digits)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # ¿Es horario permitido para ESTE teléfono? (ver nota de husos arriba)
  def self.window_open?(digits)
    if digits.to_s.start_with?('52')
      t = Time.now.in_time_zone('America/Mexico_City')
      t.hour >= 10 && t.hour < 19
    else
      t = Time.now.in_time_zone('America/New_York')
      t.hour >= 12 && t.hour < 21
    end
  end

  # Envía las pendientes que estén en ventana. Lo llama el job cada 15 min.
  def self.run_due!(limit: 60)
    return { sent: 0 } unless table_exists?

    approved = WhatsappOutbound.approved
    names = approved.map { |t| t['name'] }
    sent = 0
    waiting_tpl = 0
    pending.order(:created_at).limit(limit).each do |p|
      tpl = TPL[p.target_kind]
      next if tpl.blank?
      (waiting_tpl += 1; next) unless names.include?(tpl) # plantilla aún en revisión de Meta
      next unless window_open?(p.phone)

      p.deliver!(approved.find { |t| t['name'] == tpl })
      sent += 1 if p.reload.status == 'sent'
    end
    { sent: sent, waiting_template: waiting_tpl }
  end

  def deliver!(tpl_info)
    tpl = TPL[target_kind]
    first = ref_name.to_s.strip.split(' ').first.presence || 'contacto'
    lang = (tpl_info && tpl_info['language']).presence || 'es_MX'
    resp = WhatsappCloud.new.send_template(phone, name: tpl, lang: lang, params: [first, customer_name.to_s])

    # Archivar en el hilo de la persona con el texto real de la plantilla.
    body = (tpl_info && tpl_info['body']).to_s
    body = body.gsub('{{1}}', first).gsub('{{2}}', customer_name.to_s)
    body = "Plantilla #{tpl} para #{ref_name}" if body.blank?
    m = WhatsappMessage.new(user: contract&.user, direction: 'out', wa_phone: phone, body: body)
    m.wa_message_id = resp.dig('messages', 0, 'id') if resp.is_a?(Hash)
    m.status = 'sent' if m.has_attribute?(:status)
    m.save!
    ContactLog.create!(user_id: contract&.user_id, person_type: 'reference', person_name: ref_name,
                       phone: phone, author_name: 'Automático',
                       body: "🤖 Verificación de referencia (#{target_kind}) enviada por WhatsApp a #{ref_name}")
    update_columns(status: 'sent', sent_at: Time.current, error: nil)
  rescue StandardError => e
    n = attempts.to_i + 1
    cols = { attempts: n, error: e.message.to_s[0, 200] }
    cols[:status] = 'skipped' if n >= 20 # nunca reintentar para siempre
    update_columns(cols)
    Rails.logger.warn "[ReferencePing] ##{id} intento #{n}: #{e.message}"
  end
end
