# frozen_string_literal: true

# GATE DE REFERENCIAS — MODO SOMBRA (Spec Parte II).
# Compara lo declarado por el cliente contra lo contestado por sus referencias
# y guarda un veredicto (clear | hold | stop) con razones EN EL CONTRATO.
# En sombra NUNCA bloquea nada: el veredicto es consejo para el equipo y
# materia prima para el motor de decisión (ReferenceGateReadiness).
#
# Reglas clave (del spec):
#   - Solo la SOBREESTIMACIÓN es señal; subestimar jamás penaliza.
#   - La antigüedad laboral solo cuenta desde el ping del EMPLEADOR REAL
#     (teléfono = buyer.phone_work); un amigo en su trabajo no corrobora nada.
#   - Reclamo exactamente en el borde del rango (6 o 24 meses) con delta +1 =
#     'sobreestimo_en_limite' informativo, NO detiene (gente honesta en el borde).
#   - Una referencia nunca SUBE nada: corroborar libera, no premia.
class ReferenceGate
  BUCKET_ORD = { 'a' => 0, 'b' => 1, 'c' => 2 }.freeze
  RESPONSE_WINDOW_DAYS = 5
  HOLD_REASONS = %w[sobreestimo_antiguedad respuesta_negativa pocas_respuestas patron_uniforme].freeze

  class << self
    def ready?
      defined?(ReferenceCheck) && ReferenceCheck.table_exists? &&
        Contract.column_names.include?('reference_gate_status')
    rescue StandardError
      false
    end

    def bucket_for(months)
      m = months.to_i
      m < 6 ? 'a' : (m < 24 ? 'b' : 'c')
    end

    # Llamado por ReferenceSurvey después de CADA respuesta de botones.
    def record_answer!(ping, idx, opt_key)
      return unless ready? && ping&.contract

      write_check!(ping, opt_key) if idx.to_i.zero? && %w[domicilio trabajo].include?(ping.target_kind)
      evaluate!(ping.contract)
    end

    def write_check!(ping, opt_key)
      contract = ping.contract
      buyer = buyer_for(contract)
      if ping.target_kind == 'domicilio'
        field = 'months_address'
        claimed = (buyer&.months_address.presence || contract.user&.months_address).to_i
        source = 'domicilio'
      else
        field = 'months_job'
        claimed = contract.user&.months_job.to_i
        source = employer_ping?(ping, buyer) ? 'trabajo_empleador' : 'trabajo_referencia'
      end
      cb = bucket_for(claimed)
      delta = BUCKET_ORD.fetch(cb) - BUCKET_ORD.fetch(opt_key.to_s, 0)
      boundary = delta == 1 && [6, 24].include?(claimed)
      mins = ping.sent_at ? ((Time.current - ping.sent_at) / 60).round : nil
      chk = ReferenceCheck.find_or_initialize_by(contract_id: contract.id, reference_ping_id: ping.id, field: field)
      chk.update!(claimed_months: claimed, claimed_bucket: cb, reported_bucket: opt_key.to_s,
                  bucket_delta: delta, boundary: boundary, source_kind: source, response_minutes: mins)
    end

    # Evalúa y guarda el veredicto sombra. Las razones se ACUMULAN (no hay
    # cortocircuito) para que quien revise vea todo lo que sonó.
    def evaluate!(contract)
      return unless ready? && contract

      pings = contract.reference_pings.to_a
      return if pings.empty?

      buyer = buyer_for(contract)
      reasons = []
      reasons << 'bandera_roja' if pings.any? { |p| p.survey_state.to_s == 'red_flag' }

      checks = ReferenceCheck.where(contract_id: contract.id, source_kind: %w[domicilio trabajo_empleador])
      reasons << 'sobreestimo_antiguedad' if checks.any? { |c| c.bucket_delta.to_i >= 1 && !c.boundary }
      reasons << 'sobreestimo_en_limite'  if checks.any? { |c| c.bucket_delta.to_i == 1 && c.boundary }

      reasons << 'respuesta_negativa' if negative_key_answer?(pings)

      answered = pings.count { |p| engaged?(p) }
      all_due = pings.all? { |p| p.sent_at && p.sent_at < RESPONSE_WINDOW_DAYS.days.ago }
      reasons << 'pocas_respuestas' if pings.size >= 2 && answered < 2 && all_due

      reasons << 'patron_uniforme' if uniform_and_instant?(pings)
      reasons << 'ingreso_variable' if variable_income?(pings, buyer)

      decision = if reasons.include?('bandera_roja')
                   'stop'
                 elsif (reasons & HOLD_REASONS).any?
                   'hold'
                 else
                   'clear'
                 end

      prev = contract.reference_gate_status
      contract.update_columns(reference_gate_status: decision,
                              reference_gate_reasons: reasons.join(','),
                              reference_gate_at: Time.current)
      if prev != decision
        begin
          AuditLog.record!(actor: nil, action: 'reference_gate', target: contract,
                           label: "Gate de referencias (sombra): #{prev.presence || 'nuevo'} → #{decision}",
                           details: reasons.join(', ').presence || 'sin señales')
        rescue StandardError
          nil
        end
      end
      decision
    end

    private

    def buyer_for(contract)
      return nil unless contract.respond_to?(:orders)

      order = contract.orders.detect { |o| o.respond_to?(:buyer) && o.buyer } || contract.orders.first
      order.respond_to?(:buyer) ? order&.buyer : nil
    end

    def employer_ping?(ping, buyer)
      digits = ->(s) { d = s.to_s.gsub(/\D/, ''); d.length > 10 ? d[-10, 10] : d }
      pw = digits.call(buyer&.phone_work)
      pw.present? && digits.call(ping.phone) == pw
    end

    def parse(ping)
      j = JSON.parse(ping.answers.to_s)
      j.is_a?(Array) ? j : []
    rescue StandardError
      []
    end

    # ¿La referencia respondió ALGO? (contenido, o al menos una persona real
    # tocó un botón — "ahora no" también cuenta como persona real).
    def engaged?(ping)
      ping.answers.present? || %w[ask done red_flag deferred].include?(ping.survey_state.to_s)
    end

    # neg en las preguntas CLAVE: ¿Paga la renta a tiempo? (domicilio_1) o
    # ¿Recomendarías para un crédito? (domicilio_3). Respaldo por texto para
    # respuestas registradas antes de q_key.
    def negative_key_answer?(pings)
      pings.any? do |p|
        parse(p).any? do |e|
          next false unless e['neg']

          key = e['q_key'].to_s
          key == 'domicilio_1' || key == 'domicilio_3' ||
            (key.blank? && e['q'].to_s.match?(/renta a tiempo|Recomendar/i))
        end
      end
    end

    # ≥3 respondieron, TODAS las respuestas máximo-positivas (opción 'a') y
    # todas llegaron con minutos de diferencia: patrón de coacheo. Hipótesis a
    # medir, no regla de bloqueo (por eso solo razona el HOLD sombra).
    def uniform_and_instant?(pings)
      with_answers = pings.select { |p| parse(p).any? }
      return false if with_answers.size < 3

      entries = with_answers.flat_map { |p| parse(p) }
      return false if entries.any? { |e| e['neg'] }
      return false unless entries.all? { |e| e['opt'].to_s == 'a' || e['opt'].blank? }
      return false if entries.none? { |e| e['opt'].present? } # datos viejos sin opt: no evaluar

      times = with_answers.map { |p| parse(p).map { |e| e['at'] }.compact.first }.compact
      return false if times.size < 3

      ts = times.map { |t| Time.iso8601(t) rescue nil }.compact
      return false if ts.size < 3

      (ts.max - ts.min) <= 10 * 60
    end

    # El EMPLEADOR contestó 'Variable' o 'No sabría decir' sobre el ingreso:
    # no detiene nada — marca el expediente para apretar el tope de pago/ingreso.
    def variable_income?(pings, buyer)
      pings.any? do |p|
        next false unless p.target_kind == 'trabajo' && employer_ping?(p, buyer)

        parse(p).any? { |e| e['q_key'].to_s == 'trabajo_1' && %w[b c].include?(e['opt'].to_s) }
      end
    end
  end
end
