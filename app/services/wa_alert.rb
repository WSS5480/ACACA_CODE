# frozen_string_literal: true

# 🚨 ALERTA INTERNA por WhatsApp: si un envío/disparador automático FALLA
# (webhook, tick programado, aviso de aprobación, firma, entrevista...), se
# avisa por WhatsApp a los números del equipo configurados en
# Configuración → Respuestas WhatsApp → Alertas internas.
# La misma alerta no se repite más de una vez cada 10 minutos (anti-tormenta)
# y todo queda también en la Bitácora.
class WaAlert
  SETTING_KEY = 'wa_alert_numbers'

  class << self
    def numbers
      AppSetting.get(SETTING_KEY).to_s.split(/[,;\s]+/)
                .map { |x| x.gsub(/\D/, '') }.reject { |x| x.length < 10 }.uniq
    rescue StandardError
      []
    end

    def numbers=(raw)
      AppSetting.set(SETTING_KEY, raw.to_s.strip[0, 500])
    end

    def notify(context, error)
      key = "wa_alert_#{context.to_s.downcase.gsub(/[^a-z0-9]+/, '_')[0, 60]}"
      return if Rails.cache.read(key) # anti-tormenta: misma alerta máx. 1 vez / 10 min

      Rails.cache.write(key, 1, expires_in: 10.minutes)
      begin
        AuditLog.record!(actor: nil, action: 'auto_send_failed', label: context.to_s[0, 120],
                         details: error.to_s[0, 250])
      rescue StandardError
        nil
      end
      text = "⚠️ ALERTA interna Ácasa — falló un disparador automático.\n" \
             "📍 #{context}\n💥 #{error.to_s[0, 300]}\n" \
             "🕐 #{Time.now.in_time_zone('America/Monterrey').strftime('%d/%m %H:%M')} (Monterrey)"
      numbers.each do |n|
        resp = WhatsappCloud.new.send_text(n, text)
        m = WhatsappMessage.new(direction: 'out', wa_phone: n, body: text)
        m.wa_message_id = resp.dig('messages', 0, 'id') if resp.is_a?(Hash)
        m.status = 'sent' if m.has_attribute?(:status)
        m.save!
      rescue StandardError => e
        Rails.logger.error "[WaAlert] no se pudo avisar a #{n}: #{e.message}"
      end
    rescue StandardError => e
      Rails.logger.error "[WaAlert] #{e.message}"
    end
  end
end
