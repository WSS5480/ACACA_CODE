# frozen_string_literal: true

# MINI-ENTREVISTA por WhatsApp a referencias, contacto de domicilio y trabajo.
# Cuando la persona nos escribe (tocando el enlace del paquete de reenvío), su
# ventana de 24 h se abre y le preguntamos con BOTONES:
#   1) "(Cliente) está solicitando crédito en Ácasa... ¿Recomiendas a (cliente)?"
#      [Sí, lo recomiendo] [No]
#      - No  -> gracias + invitación a solicitar su propio crédito (enlace).
#      - Sí  -> 2) ¿Desde hace cuánto lo conoces / vive ahí / trabaja ahí?
#               [Menos de 6 meses] [1 a 2 años] [Más de 2 años] -> gracias + enlace.
# Las respuestas se guardan en reference_pings (recommends, time_known) y en el
# historial del cliente. Todo se archiva en la bandeja de WhatsApp.
class ReferenceSurvey
  STORE = 'https://www.acasamx.com'
  TIME_LABELS = { 'a' => 'Menos de 6 meses', 'b' => '1 a 2 años', 'c' => 'Más de 2 años' }.freeze
  KIND_PRIORITY = { 'domicilio' => 0, 'trabajo' => 1, 'personal' => 2 }.freeze

  class << self
    def enabled?
      defined?(ReferencePing) && ReferencePing.table_exists? &&
        ReferencePing.column_names.include?('survey_state')
    end

    # Entrada de TEXTO libre de un teléfono: si es una referencia pendiente,
    # se marca "respondio" y se le manda la primera pregunta con botones.
    def on_inbound(from)
      return unless defined?(ReferencePing) && ReferencePing.table_exists?

      tail = from.to_s.gsub(/\D/, '')[-10..]
      return if tail.blank?

      pings = ReferencePing.pending.where('phone LIKE ?', "%#{tail}").to_a
      return if pings.empty?

      pings.each do |p|
        p.update_columns(status: 'respondio', sent_at: Time.current, error: nil)
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "✅ #{p.ref_name} (#{p.target_kind}) nos escribió por WhatsApp: verificación en curso")
      end
      return unless enabled?

      # UNA sola entrevista por teléfono: la del tipo más específico.
      target = pings.min_by { |p| [KIND_PRIORITY[p.target_kind] || 9, -p.id] }
      return if target.nil? || target.survey_state.present?

      ask_q1(target)
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] on_inbound: #{e.message}"
    end

    # Respuesta de BOTÓN (webhook type 'interactive'). id = rs<ping>q1s|q1n|q2a|q2b|q2c
    def handle_button(from:, id:, title: nil)
      m = id.to_s.match(/\Ars(\d+)q([12])([a-z])\z/)
      return false unless m && enabled?

      p = ReferencePing.find_by(id: m[1].to_i)
      return true unless p # botón viejo: no reprocesar como texto

      cust = p.customer_name.to_s
      case [m[2], m[3]]
      in ['1', 's']
        p.update_columns(recommends: 'si', survey_state: 'q2')
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "📋 #{p.ref_name} (#{p.target_kind}) SÍ recomienda a #{cust}")
        ask_q2(p)
      in ['1', 'n']
        p.update_columns(recommends: 'no', survey_state: 'done')
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "📋 ⚠ #{p.ref_name} (#{p.target_kind}) NO recomienda a #{cust}")
        say(p, '¡Muchas gracias por tu tiempo! 🙏 Y si a ti te gustaría solicitar crédito ' \
               "con Ácasa, entra aquí: #{STORE}")
      in ['2', String => c] if TIME_LABELS.key?(c)
        label = TIME_LABELS[c]
        p.update_columns(time_known: label, survey_state: 'done')
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "📋 #{p.ref_name} (#{p.target_kind}) — tiempo: #{label}")
        say(p, '¡Listo, mil gracias! 🙌 Eso era todo. Si a ti también te gustaría estrenar ' \
               "con crédito Ácasa, visítanos: #{STORE}")
      else
        return true
      end
      true
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] handle_button: #{e.message}"
      true
    end

    private

    def ask_q1(p)
      cust = p.customer_name.to_s
      first = p.ref_name.to_s.split.first.presence || 'hola'
      pitch = "#{cust} está solicitando crédito en Ácasa, un gran servicio nuevo: " \
              'enviarle a la gente que más quieres ¡lo que necesita! 🎁'
      body = case p.target_kind
             when 'domicilio'
               "Hola #{first}! 👋 #{pitch} Nos compartió este número como su contacto de domicilio. ¿Recomiendas a #{cust}?"
             when 'trabajo'
               "Hola, buen día 👋 #{pitch} Nos compartió este número como referencia de su trabajo. ¿Recomiendas a #{cust}?"
             else
               "Hola #{first}! 👋 #{pitch} Te puso como su referencia. ¿Recomiendas a #{cust}?"
             end
      buttons = [{ id: "rs#{p.id}q1s", title: 'Sí, lo recomiendo' },
                 { id: "rs#{p.id}q1n", title: 'No' }]
      send_and_archive(p, body, buttons)
      p.update_columns(survey_state: 'q1')
    end

    def ask_q2(p)
      cust = p.customer_name.to_s
      q = case p.target_kind
          when 'domicilio' then "¡Gracias! 🙌 ¿Cuánto tiempo tiene #{cust} viviendo en el domicilio?"
          when 'trabajo'   then "¡Gracias! 🙌 ¿Cuánto tiempo tiene #{cust} trabajando ahí?"
          else                  "¡Gracias! 🙌 ¿Desde hace cuánto conoces a #{cust}?"
          end
      buttons = [{ id: "rs#{p.id}q2a", title: 'Menos de 6 meses' },
                 { id: "rs#{p.id}q2b", title: '1 a 2 años' },
                 { id: "rs#{p.id}q2c", title: 'Más de 2 años' }]
      send_and_archive(p, q, buttons)
    end

    def say(p, text)
      resp = WhatsappCloud.new.send_text(p.phone, text)
      archive(p, text, resp)
    end

    def send_and_archive(p, body, buttons)
      resp = WhatsappCloud.new.send_buttons(p.phone, body: body, buttons: buttons)
      labels = buttons.map { |b| "[#{b[:title]}]" }.join(' ')
      archive(p, "#{body}\n#{labels}", resp)
    end

    def archive(p, body, resp)
      m = WhatsappMessage.new(user: p.contract&.user, direction: 'out', wa_phone: p.phone, body: body)
      m.wa_message_id = resp.dig('messages', 0, 'id') if resp.is_a?(Hash)
      m.status = 'sent' if m.has_attribute?(:status)
      m.save!
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] archive: #{e.message}"
    end
  end
end
