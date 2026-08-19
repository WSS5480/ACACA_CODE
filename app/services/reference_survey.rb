# frozen_string_literal: true

# ENTREVISTA por WhatsApp a referencias, dueño de casa y empleador.
# TODO es de OPCIÓN MÚLTIPLE: cada pregunta llega con botones y se contesta con
# UN toque (nada de texto libre). Una pregunta a la vez, en tiempo real, y las
# opciones usan los MISMOS rangos del proceso de aprobación de crédito
# (menos de 6 meses / 6 meses a 2 años / más de 2 años).
#
#   - Cada respuesta -> historial del cliente (ContactLog) y bandeja de WhatsApp.
#   - Transcripción completa -> reference_pings.answers (JSON).
#   - Respuesta NEGATIVA (no recomienda, no paga, etc.) -> ⚠ en el historial.
#   - Si escriben "no lo conozco" / "número equivocado" -> 🚩 BANDERA ROJA.
#
# Apertura: "Hola [Nombre], te contacto de Ácasa porque [Cliente] te nombró
# como referencia para validar un crédito. ¿Tienes 5 min...?" [Sí][Ahora no]
class ReferenceSurvey
  STORE = 'https://www.acasamx.com'
  KIND_PRIORITY = { 'domicilio' => 0, 'trabajo' => 1, 'personal' => 2 }.freeze

  RED_FLAG_PHRASES = ['no lo conozco', 'no la conozco', 'no conozco', 'no sé quién', 'no se quien',
                      'quién es', 'quien es', 'numero equivocado', 'número equivocado'].freeze

  # Máx. 4 preguntas · 3 opciones por pregunta (límite de botones de WhatsApp).
  # neg: true marca la opción como respuesta NEGATIVA (baja la recomendación).
  QUESTIONS = {
    'domicilio' => [
      { q: '¿Cuánto tiempo lleva %{cust} viviendo en tu propiedad?',
        opts: [{ t: 'Menos de 6 meses' }, { t: '6 meses a 2 años' }, { t: 'Más de 2 años' }] },
      { q: '¿Paga la renta a tiempo?',
        opts: [{ t: 'Sí, siempre' }, { t: 'A veces se atrasa' }, { t: 'No paga a tiempo', neg: true }] },
      { q: '¿Es buen inquilino? (conducta, cuidado de la propiedad)',
        opts: [{ t: 'Sí, sin problemas' }, { t: 'Algunos problemas' }, { t: 'No lo recomiendo', neg: true }] },
      { q: '¿Recomendarías a %{cust} para un crédito?',
        opts: [{ t: 'Sí, lo recomiendo' }, { t: 'Tengo dudas' }, { t: 'No', neg: true }] }
    ],
    'trabajo' => [
      { q: '¿Cuánto tiempo tiene %{cust} trabajando ahí?',
        opts: [{ t: 'Menos de 6 meses' }, { t: '6 meses a 2 años' }, { t: 'Más de 2 años' }] },
      { q: '¿Su ingreso es fijo o variable?',
        opts: [{ t: 'Fijo' }, { t: 'Variable' }, { t: 'No sabría decir' }] },
      { q: '¿Su empleo es estable?',
        opts: [{ t: 'Sí, permanente' }, { t: 'Temporal' }, { t: 'Está por terminar', neg: true }] },
      { q: '¿Tiene buen desempeño y asistencia?',
        opts: [{ t: 'Sí, muy bueno' }, { t: 'Regular' }, { t: 'Con problemas', neg: true }] }
    ],
    'personal' => [
      { q: '¿Desde hace cuánto conoces a %{cust}?',
        opts: [{ t: 'Menos de 6 meses' }, { t: '6 meses a 2 años' }, { t: 'Más de 2 años' }] },
      { q: '¿Es persona de palabra? ¿Cumple sus compromisos?',
        opts: [{ t: 'Sí, siempre' }, { t: 'La mayoría de veces' }, { t: 'No', neg: true }] },
      { q: '¿Confiarías en que pagará un crédito puntualmente?',
        opts: [{ t: 'Sí, sin duda' }, { t: 'Probablemente sí' }, { t: 'No', neg: true }] },
      { q: '¿Recomiendas a %{cust}?',
        opts: [{ t: 'Sí, lo recomiendo' }, { t: 'Tengo dudas' }, { t: 'No', neg: true }] }
    ]
  }.freeze
  OPT_KEYS = %w[a b c].freeze

  class << self
    def enabled?
      defined?(ReferencePing) && ReferencePing.table_exists? &&
        ReferencePing.column_names.include?('survey_state') &&
        ReferencePing.column_names.include?('answers')
    end

    # TEXTO libre entrante:
    #   - Entrevista en curso -> revisar bandera roja y RE-ENVIAR la pregunta con
    #     sus botones (las respuestas son SOLO de opción múltiple).
    #   - Referencia pendiente -> marcar "respondio" y mandar la apertura.
    def on_inbound(from, body = nil)
      return unless defined?(ReferencePing) && ReferencePing.table_exists?

      tail = from.to_s.gsub(/\D/, '')[-10..]
      return if tail.blank?

      if enabled?
        live = ReferencePing.where(survey_state: %w[opener ask]).where('phone LIKE ?', "%#{tail}").order(:id).last
        if live
          return red_flag!(live, body) if red_flag_text?(body)
          return live.survey_state == 'opener' ? send_opener(live) : ask_current(live)
        end
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
      WaAlert.notify('Entrevista de referencias (inicio)', e.message) if defined?(WaAlert)
    end

    # BOTONES: rs<ping>ok / rs<ping>no (apertura) · rs<ping>q<idx><a|b|c> (preguntas)
    def handle_button(from:, id:, title: nil)
      return false unless enabled?

      if (m = id.to_s.match(/\Ars(\d+)(ok|no)\z/))
        p = ReferencePing.find_by(id: m[1].to_i)
        return true unless p

        if m[2] == 'ok'
          p.update_columns(survey_state: 'ask', question_idx: 0)
          ask_current(p)
        else
          p.update_columns(survey_state: 'deferred')
          say(p, WaAutoText.text('ent_despues'))
          ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                             person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                             body: "📋 #{p.ref_name} (#{p.target_kind}) pidió que le escribamos MÁS TARDE (entrevista pospuesta)")
        end
        return true
      end

      if (m = id.to_s.match(/\Ars(\d+)q(\d+)([a-c])\z/))
        p = ReferencePing.find_by(id: m[1].to_i)
        return true unless p

        record_choice(p, m[2].to_i, m[3])
        return true
      end

      false
    rescue StandardError => e
      Rails.logger.warn "[ReferenceSurvey] handle_button: #{e.message}"
      WaAlert.notify('Entrevista de referencias (botones)', e.message) if defined?(WaAlert)
      true
    end

    private

    def script_for(p)
      QUESTIONS[%w[domicilio trabajo].include?(p.target_kind) ? p.target_kind : 'personal']
    end

    def send_opener(p)
      first = p.ref_name.to_s.split.first.presence || 'hola'
      rol = case p.target_kind
            when 'domicilio' then 'como su dueño de casa'
            when 'trabajo'   then 'como referencia de su trabajo'
            else                  'como referencia'
            end
      # Texto EDITABLE en Configuración → Respuestas WhatsApp.
      body = WaAutoText.render('ent_apertura', referencia: first, cliente: p.customer_name, rol: rol)
      resp = WhatsappCloud.new.send_buttons(p.phone, body: body,
                                            buttons: [{ id: "rs#{p.id}ok", title: 'Sí, adelante' },
                                                      { id: "rs#{p.id}no", title: 'Ahora no' }])
      archive(p, "#{body}\n[Sí, adelante] [Ahora no]", resp)
      p.update_columns(survey_state: 'opener')
    end

    def ask_current(p)
      qs = script_for(p)
      i = p.question_idx.to_i
      return finish(p) if i >= qs.length

      spec = qs[i]
      body = format(spec[:q], cust: p.customer_name.to_s)
      buttons = spec[:opts].each_with_index.map { |o, j| { id: "rs#{p.id}q#{i}#{OPT_KEYS[j]}", title: o[:t] } }
      resp = WhatsappCloud.new.send_buttons(p.phone, body: "#{i + 1}/#{qs.length} · #{body}", buttons: buttons)
      archive(p, "#{i + 1}/#{qs.length} · #{body}\n#{spec[:opts].map { |o| "[#{o[:t]}]" }.join(' ')}", resp)
    end

    def record_choice(p, idx, key)
      qs = script_for(p)
      return ask_current(p) if idx != p.question_idx.to_i || idx >= qs.length # botón viejo/repetido

      spec = qs[idx]
      opt = spec[:opts][OPT_KEYS.index(key) || 0] || spec[:opts].first
      q = format(spec[:q], cust: p.customer_name.to_s)

      log = begin
        JSON.parse(p.answers.to_s)
      rescue StandardError
        []
      end
      log = [] unless log.is_a?(Array)
      log << { 'q' => q, 'a' => opt[:t], 'neg' => !!opt[:neg] }
      cols = { answers: log.to_json, question_idx: idx + 1 }
      cols[:time_known] = opt[:t] if idx.zero? && p.respond_to?(:time_known)
      p.update_columns(cols)

      ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                         person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                         body: "📋#{opt[:neg] ? ' ⚠' : ''} #{p.ref_name} (#{p.target_kind}) — #{q} → #{opt[:t]}")

      ask_current(p.reload)
    end

    def finish(p)
      log = begin
        JSON.parse(p.answers.to_s)
      rescue StandardError
        []
      end
      negs = log.is_a?(Array) ? log.count { |x| x['neg'] } : 0
      p.update_columns(survey_state: 'done')
      p.update_columns(recommends: negs.positive? ? 'no' : 'si') if p.respond_to?(:recommends)
      # Cierre con BOTÓN humano (sin URL fea): "Conocer Ácasa" abre la tienda.
      body = WaAutoText.text('ent_gracias') # editable en Configuración → Respuestas WhatsApp
      resp = WhatsappCloud.new.send_link_button(p.phone, body: body, button_text: '🛍 Conocer Ácasa', url: STORE)
      archive(p, "#{body}\n[🛍 Conocer Ácasa]", resp)
      ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                         person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                         body: negs.positive? ? "⚠ Entrevista COMPLETA de #{p.ref_name} (#{p.target_kind}) con #{negs} respuesta(s) NEGATIVA(s) — revisar antes de aprobar" : "✅ Entrevista COMPLETA de #{p.ref_name} (#{p.target_kind}) — todo favorable")
    end

    def red_flag_text?(body)
      low = body.to_s.downcase
      low.present? && RED_FLAG_PHRASES.any? { |f| low.include?(f) }
    end

    def red_flag!(p, body)
      p.update_columns(survey_state: 'red_flag')
      p.update_columns(recommends: 'no') if p.respond_to?(:recommends)
      ContactLog.create!(user_id: p.contract&.user_id, person_type: 'reference',
                         person_name: p.ref_name, phone: p.phone, author_name: 'Automático',
                         body: "🚩 BANDERA ROJA: #{p.ref_name} (#{p.target_kind}) indica NO conocer a #{p.customer_name} (\"#{body.to_s[0, 120]}\") — revisar antes de aprobar")
      say(p, WaAutoText.text('ent_flag'))
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
