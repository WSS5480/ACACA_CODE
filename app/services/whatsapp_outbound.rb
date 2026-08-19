# frozen_string_literal: true

# ENVÍO AUTOMÁTICO de WhatsApp desde la plataforma (firma de contrato,
# recordatorios de pago, carrito abandonado, primer contacto).
#
# Regla de WhatsApp: el texto libre SÓLO se entrega si la persona nos escribió
# en las últimas 24 horas; fuera de esa ventana Meta lo acepta y lo DESCARTA sin
# avisar. Por eso aquí: se intenta texto libre (gratis dentro de la ventana) y,
# si Meta responde que la ventana está cerrada, se reenvía como PLANTILLA
# aprobada — que sí llega siempre.
class WhatsappOutbound
  # Evento -> plantilla por omisión (se puede cambiar en Ajustes sin tocar código)
  DEFAULTS = {
    'firma'    => 'firma_contrato',
    'pago'     => 'recordatorio_pago',
    'carrito'  => 'carrito_pendiente',
    'contacto' => 'contacto_inicial',
    'aprobada' => 'cuenta_aprobada'
  }.freeze
  SETTING_KEY = 'wa_auto_templates'

  class << self
    # Mapa evento -> nombre de plantilla (BD o valores por omisión).
    def template_map
      saved = begin
        JSON.parse(AppSetting.get(SETTING_KEY).to_s)
      rescue StandardError
        {}
      end
      DEFAULTS.merge(saved.is_a?(Hash) ? saved.slice(*DEFAULTS.keys) : {})
    end

    def template_map=(hash)
      AppSetting.set(SETTING_KEY, DEFAULTS.merge((hash || {}).slice(*DEFAULTS.keys)).to_json)
    end

    # Plantillas aprobadas (cacheadas 10 min para no consultar a Meta en cada envío).
    def approved
      Rails.cache.fetch('wa_approved_templates', expires_in: 10.minutes) { WhatsappCloud.new.templates }
    rescue StandardError
      []
    end

    def language_for(name)
      (approved.find { |t| t['name'] == name } || {})['language'].presence || 'es_MX'
    end

    # Envía y ARCHIVA el mensaje en el expediente de la persona.
    # event: 'firma' | 'pago' | 'carrito' | 'contacto' (nil = sólo texto libre)
    # params: valores de la plantilla, en orden ({{1}}, {{2}}...)
    # Devuelve { ok:, via: 'texto'|'plantilla', error: }
    def deliver(phone:, text:, event: nil, params: [], user: nil, actor: nil)
      return { ok: false, error: 'La persona no tiene teléfono registrado' } if phone.to_s.strip.blank?

      wa = WhatsappCloud.new
      via = 'texto'
      resp = begin
        wa.send_text(phone, text)
      rescue WhatsappCloud::DeliveryError => e
        raise e unless event && WhatsappCloud.window_error?(e.message)

        tpl = template_map[event.to_s]
        raise e if tpl.blank?

        via = 'plantilla'
        wa.send_template(phone, name: tpl, lang: language_for(tpl), params: params)
      end

      archive(user: user, phone: phone, text: text, resp: resp, actor: actor, via: via)
      { ok: true, via: via, sent_to: phone }
    rescue WhatsappCloud::NotConfigured
      { ok: false, error: 'WhatsApp no está configurado en el servidor' }
    rescue StandardError => e
      { ok: false, error: e.message }
    end

    private

    def archive(user:, phone:, text:, resp:, actor:, via:)
      m = WhatsappMessage.new(user: user, direction: 'out',
                              wa_phone: WhatsappCloud.normalize_phone(phone),
                              body: text, sent_by_id: actor&.id)
      m.wa_message_id = resp.dig('messages', 0, 'id') if resp.is_a?(Hash)
      m.status = 'sent' if m.has_attribute?(:status)
      m.save!
      Rails.logger.info "[WhatsappOutbound] enviado por #{via} a #{phone}"
      m
    rescue StandardError => e
      Rails.logger.error "[WhatsappOutbound] no se pudo archivar: #{e.message}"
      nil
    end
  end
end
