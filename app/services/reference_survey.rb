# frozen_string_literal: true

# ENTREVISTA por WhatsApp a referencias, dueño de casa y empleador — guion de
# verificación de crédito. UNA pregunta a la vez (no abrumar), esperando la
# respuesta antes de la siguiente. Todo queda documentado:
#   - Cada pregunta/respuesta -> historial del cliente (ContactLog) y bandeja.
#   - Transcripción completa   -> reference_pings.answers (JSON).
#   - 🚩 BANDERA ROJA automática si la referencia dice NO conocer al cliente.
#
# Guiones por tipo de contacto:
#   domicilio        -> DUEÑO DE CASA: tiempo viviendo, dirección, puntualidad
#                       de renta, monto, conducta, permanencia.
#   trabajo          -> EMPLEADOR: puesto y antigüedad, salario, contrato,
#                       desempeño, documentación.
#   personal (+52)   -> REFERENCIA EN MÉXICO: relación, ocupación, palabra,
#                       préstamos, ingreso en USA, deudas, dónde vive (antifraude).
#   personal (EE.UU.)-> REFERENCIA EN USA: relación, situación laboral,
#                       confiabilidad, capacidad de pago.
#
# Apertura (con botones): "Hola [Nombre], te contacto de Ácasa porque [Cliente]
# te nombró como referencia para validar un crédito. ¿Tienes 5 min...?"
class ReferenceSurvey
  STORE = 'https://www.acasamx.com'
  KIND_PRIORITY = { 'domicilio' => 0, 'trabajo' => 1, 'personal' => 2 }.freeze

  RED_FLAG_PHRASES = ['no lo conozco', 'no la conozco', 'no conozco', 'no sé quién', 'no se quien',
                      'quién es', 'quien es', 'numero equivocado', 'número equivocado'].freeze

  # MÁXIMO 4 preguntas por entrevista (no abrumar por WhatsApp).
  QUESTIONS = {
    'domicilio' => [
      '¿Cuánto tiempo lleva %{cust} viviendo en tu propiedad?',
      '¿Cuál es la dirección exacta de la propiedad?',
      '¿Paga la renta a tiempo y de cuánto es la renta mensual?',
      '¿Es buen inquilino? ¿Algún problema de conducta o daños?'
    ],
    'trabajo' => [
      '¿Cuál es el puesto o cargo de %{cust}? ¿Desde cuándo trabaja con ustedes?',
      '¿Cuál es su salario mensual aproximado? ¿Es fijo o variable?',
      '¿Tiene contrato permanente o temporal? ¿Cuándo vence?',
      '¿Tiene buen desempeño? ¿Ausencias o problemas de conducta?'
    ],
    'personal_mx' => [
      '¿Cuánto tiempo llevas conociendo a %{cust}? ¿Cómo se conocen?',
      '¿Es persona de palabra? ¿Ha cumplido compromisos contigo?',
      '¿Te ha pedido dinero prestado alguna vez? ¿Lo devolvió?',
      '¿Dónde está viviendo %{cust} ahora?'
    ],
    'personal_us' => [
      '¿Cuánto tiempo llevas conociendo a %{cust}? ¿Cómo se conocen?',
      '¿Cuál es su situación laboral? ¿Tiene trabajo estable?',
      '¿Es persona confiable? ¿Ha cumplido compromisos contigo?',
      '¿Conoces su situación económica? ¿Su capacidad de pago?'
    ]
  }.freeze

  class << self
    def enabled?
      defined?(ReferencePing) && ReferencePing.table_exists? &&
        ReferencePing.column_names.include?('survey_state') &&
        ReferencePing.column_names.include?('answers')
    end

    # TEXTO entrante de un teléfono:
    #   1) ¿Hay entrevista EN CURSO con este número? -> el texto es la RESPUESTA.
    #   2) ¿Es referencia pendiente? -> marcar "respondio" y mandar la apertura.
    def on_inbound(from, body = nil)
      return unless defined?(ReferencePing) && ReferencePing.table_exists?

      tail = from.to_s.gsub(/\D/, '')[-10..]
      return if tail.blank?

      if enabled?
        live = ReferencePing.where(survey_state: 'ask').where('phone LIKE ?', "%#{tail}").order(:id).last
        return record_answer(live, body) if live
      end

      pings = ReferencePing.pending.where('phone LIKE ?', "%#{tail}").to_a
      return if pings.empty?

      pings.each do |p|
        p.update_columns(status: 'respondio', sent_at: Time.current, error: nil)
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "✅ #{p.ref_name} (#{p.target_kind}) nos escribió por WhatsApp: verificación en curso")
      end
      return unless enabled?

      target = pings.min_by { |p| [KIND_PRIORITY[p.target_kind] || 9, -p.id] }
      return if target.nil? || target.survey_state.present?

      send_opener(target)
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] on_inbound: #{e.message}"
    end

    # Botones de la APERTURA: rs<ping>ok / rs<ping>no
    def handle_button(from:, id:, title: nil)
      m = id.to_s.match(/\Ars(\d+)(ok|no)\z/)
      return false unless m && enabled?

      p = ReferencePing.find_by(id: m[1].to_i)
      return true unless p

      if m[2] == 'ok'
        p.update_columns(survey_state: 'ask', question_idx: 0)
        ask_next(p)
      else
        p.update_columns(survey_state: 'deferred')
        say(p, 'Sin problema 🙏 Te escribimos más tarde. ¡Que tengas excelente día!')
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "📋 #{p.ref_name} (#{p.target_kind}) pidió que le escribamos MÁS TARDE (entrevista pospuesta)")
      end
      true
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] handle_button: #{e.message}"
      true
    end

    private

    def script_for(p)
      return QUESTIONS['domicilio'] if p.target_kind == 'domicilio'
      return QUESTIONS['trabajo'] if p.target_kind == 'trabajo'

      p.phone.to_s.start_with?('52') ? QUESTIONS['personal_mx'] : QUESTIONS['personal_us']
    end

    def send_opener(p)
      first = p.ref_name.to_s.split.first.presence || 'hola'
      rol = case p.target_kind
            when 'domicilio' then 'como su dueño de casa'
            when 'trabajo'   then 'como referencia de su trabajo'
            else                  'como referencia'
            end
      body = "Hola #{first}, te contacto de Ácasa porque #{p.customer_name} te nombró #{rol} " \
             'para validar un crédito. ¿Tienes 5 min para responder unas preguntas?'
      resp = WhatsappCloud.new.send_buttons(p.phone, body: body,
                                            buttons: [{ id: "rs#{p.id}ok", title: 'Sí, adelante' },
                                                      { id: "rs#{p.id}no", title: 'Ahora no' }])
      archive(p, "#{body}\n[Sí, adelante] [Ahora no]", resp)
      p.update_columns(survey_state: 'opener')
    end

    def ask_next(p)
      qs = script_for(p)
      i = p.question_idx.to_i
      if i >= qs.length
        finish(p)
      else
        q = format(qs[i], cust: p.customer_name.to_s)
        say(p, q)
      end
    end

    def record_answer(p, body)
      text = body.to_s.strip
      return if text.blank? # foto/audio sin texto: se queda en la misma pregunta

      qs = script_for(p)
      i = p.question_idx.to_i
      q = i < qs.length ? format(qs[i], cust: p.customer_name.to_s) : '(extra)'

      log = begin
        JSON.parse(p.answers.to_s)
      rescue StandardError
        []
      end
      log = [] unless log.is_a?(Array)
      log << { 'q' => q, 'a' => text }
      p.update_columns(answers: log.to_json, question_idx: i + 1)

      ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                         person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                         body: "📋 #{p.ref_name} (#{p.target_kind}) — #{q} → #{text[0, 300]}")

      # 🚩 Bandera roja automática: dice no conocer al cliente / número equivocado.
      low = text.downcase
      if RED_FLAG_PHRASES.any? { |f| low.include?(f) }
        p.update_columns(survey_state: 'red_flag')
        p.update_columns(recommends: 'no') if p.respond_to?(:recommends)
        ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                           person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                           body: "🚩 BANDERA ROJA: #{p.ref_name} (#{p.target_kind}) indica NO conocer a #{p.customer_name} — revisar antes de aprobar")
        say(p, 'Entendido, muchas gracias por tu tiempo 🙏 ¡Que tengas buen día!')
        return
      end

      ask_next(p.reload)
    end

    def finish(p)
      p.update_columns(survey_state: 'done')
      p.update_columns(recommends: 'si') if p.respond_to?(:recommends) && p.recommends.blank?
      say(p, '¡Listo, mil gracias por tu ayuda! 🙌 Eso era todo. Y si a ti también te gustaría ' \
             "estrenar con crédito Ácasa, visítanos: #{STORE}")
      ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                         person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                         body: "✅ Entrevista COMPLETA de #{p.ref_name} (#{p.target_kind}) — respuestas en el historial")
    end

    def say(p, text)
      resp = WhatsappCloud.new.send_text(p.phone, text)
      archive(p, text, resp)
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
