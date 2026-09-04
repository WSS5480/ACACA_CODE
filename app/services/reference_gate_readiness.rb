# frozen_string_literal: true

# MOTOR DE DECISIÓN del gate de referencias (Fase 6½ del plan).
# Corre DIARIO sobre todo el libro madurado y juzga cada regla con estadística
# real: tasa de pago malo cuando la regla disparó vs cuando no, lift y prueba z
# de dos proporciones (95%). Emite veredictos por regla y UNA recomendación:
#   ENCENDER  -> la evidencia alcanza: enciende la Fase 7 con las reglas nombradas
#   AJUSTAR   -> sigue en sombra, elimina las reglas muertas nombradas
#   ESPERAR   -> aún no hay datos suficientes
# Cada cambio de veredicto o recomendación queda en la Bitácora y en el banner
# del admin. El motor ACONSEJA; el switch lo mueve una persona, siempre.
class ReferenceGateReadiness
  RULES = %w[sobreestimo_antiguedad respuesta_negativa pocas_respuestas patron_uniforme].freeze
  DEFAULTS = {
    'season_days'     => 90,   # el contrato debe tener 90 días para juzgarse
    'late_days'       => 7,    # cuota vencida = >7 días de atraso
    'bad_min_overdue' => 2,    # 'pago malo' = 2+ cuotas vencidas
    'min_fired'       => 25,   # mínimo de disparos por regla
    'min_clean'       => 50,   # mínimo de limpios
    'min_lift'        => 1.5,  # el disparo debe multiplicar el riesgo 1.5x
    'z_crit'          => 1.96, # 95% de confianza
    'min_volume'      => 100,  # gates evaluados antes de recomendar encender
    'max_hold_rate'   => 0.35  # si el gate detiene a más del 35%, fricciona de más
  }.freeze
  KEY  = 'reference_gate_findings'
  HKEY = 'reference_gate_findings_history'

  class << self
    def config
      saved = begin
        JSON.parse(AppSetting.get('reference_gate_readiness_config').to_s)
      rescue StandardError
        {}
      end
      DEFAULTS.merge(saved.is_a?(Hash) ? saved : {})
    end

    def evaluate!
      cfg = config
      volume_all = Contract.where.not(reference_gate_status: nil).count
      holds = Contract.where(reference_gate_status: %w[hold stop]).count
      hold_rate = volume_all.positive? ? (holds.to_f / volume_all).round(3) : 0.0

      seasoned = Contract.where.not(reference_gate_status: nil)
                         .where.not(status: 'cancelled')
                         .where('contracts.created_at <= ?', cfg['season_days'].to_i.days.ago)
                         .includes(:contract_installments)
      rows = seasoned.map { |c| { reasons: c.reference_gate_reasons.to_s.split(','), bad: bad?(c, cfg) } }

      rules = {}
      RULES.each do |r|
        fired = rows.select { |x| x[:reasons].include?(r) }
        clean = rows.reject { |x| x[:reasons].include?(r) }
        n1 = fired.size
        n0 = clean.size
        b1 = fired.count { |x| x[:bad] }
        b0 = clean.count { |x| x[:bad] }
        p1 = n1.positive? ? b1.to_f / n1 : nil
        p0 = n0.positive? ? b0.to_f / n0 : nil
        lift = nil
        z = nil
        if n1.positive? && n0.positive?
          lift = if p0&.positive?
                   (p1 / p0).round(2)
                 else
                   p1&.positive? ? 99.0 : 1.0
                 end
          pooled = (b1 + b0).to_f / (n1 + n0)
          se = Math.sqrt(pooled * (1 - pooled) * (1.0 / n1 + 1.0 / n0))
          z = se.positive? ? ((p1 - p0) / se).round(2) : 0.0
        end
        verdict = if n1 >= cfg['min_fired'].to_i && n0 >= cfg['min_clean'].to_i && !z.nil?
                    if z >= cfg['z_crit'].to_f && lift.to_f >= cfg['min_lift'].to_f
                      'predice'
                    elsif z < 1.0
                      'no_predice'
                    else
                      'datos_insuficientes'
                    end
                  else
                    'datos_insuficientes'
                  end
        rules[r] = { 'n_disparo' => n1, 'n_limpio' => n0,
                     'malo_disparo' => p1&.round(3), 'malo_limpio' => p0&.round(3),
                     'lift' => lift, 'z' => z, 'veredicto' => verdict }
      end

      predice = rules.select { |_, v| v['veredicto'] == 'predice' }.keys
      muertas = rules.select { |_, v| v['veredicto'] == 'no_predice' }.keys
      if predice.any? && volume_all >= cfg['min_volume'].to_i && hold_rate <= cfg['max_hold_rate'].to_f
        rec = 'ENCENDER'
        guia = "La evidencia alcanza: enciende la Fase 7 aplicando #{predice.join(', ')}." \
               "#{muertas.any? ? " Elimina las reglas muertas: #{muertas.join(', ')}." : ''}" \
               ' El cambio va como configuración firmada; una persona mueve el switch.'
      elsif muertas.any? && rows.size >= cfg['min_volume'].to_i
        rec = 'AJUSTAR'
        guia = "Sigue en sombra. Elimina las reglas que NO predicen (#{muertas.join(', ')}) para no frenar buenos clientes" \
               "#{predice.any? ? "; #{predice.join(', ')} sí predice pero falta volumen o baja la tasa de HOLD (#{(hold_rate * 100).round}%)" : ''}."
      else
        faltan = [cfg['min_volume'].to_i - volume_all, 0].max
        rec = 'ESPERAR'
        guia = "Aún no hay evidencia para encender: #{rows.size} contratos madurados de #{volume_all} evaluados" \
               "#{faltan.positive? ? " (faltan ~#{faltan} gates para el volumen mínimo)" : ''}." \
               ' Cada regla necesita ~25 disparos madurados para juzgarse.'
      end

      snapshot = { 'computed_at' => Time.current.iso8601, 'volumen_evaluado' => volume_all,
                   'madurados' => rows.size, 'tasa_hold' => hold_rate, 'reglas' => rules,
                   'recomendacion' => rec, 'guia' => guia, 'config' => cfg }

      prev = begin
        JSON.parse(AppSetting.get(KEY).to_s)
      rescue StandardError
        nil
      end
      AppSetting.set(KEY, snapshot.to_json)

      hist = begin
        JSON.parse(AppSetting.get(HKEY).to_s)
      rescue StandardError
        []
      end
      hist = [] unless hist.is_a?(Array)
      hist << { 'at' => snapshot['computed_at'], 'rec' => rec,
                'veredictos' => rules.transform_values { |v| v['veredicto'] } }
      AppSetting.set(HKEY, hist.last(90).to_json)

      changed = prev.nil? || prev['recomendacion'] != rec ||
                (prev['reglas'] || {}).transform_values { |v| v['veredicto'] } != rules.transform_values { |v| v['veredicto'] }
      if changed
        begin
          AuditLog.record!(actor: nil, action: 'reference_gate_findings',
                           label: "Motor de decisión (referencias): #{rec}", details: guia.to_s[0, 250])
        rescue StandardError
          nil
        end
      end
      snapshot
    end

    # 'Pago malo' = bad_min_overdue+ cuotas con más de late_days de atraso hoy.
    # Misma tabla de cuotas que usa cobranza — nada inventado.
    def bad?(contract, cfg)
      limit = cfg['late_days'].to_i.days.ago.to_date
      late = contract.contract_installments.count { |i| i.status != 'paid' && i.due_date && i.due_date < limit }
      late >= cfg['bad_min_overdue'].to_i
    end
  end
end
