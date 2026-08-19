# frozen_string_literal: true

# RESPUESTAS AUTOMÁTICAS de WhatsApp — repositorio EDITABLE (Configuración →
# Respuestas WhatsApp). Cada texto vive en la base (AppSetting) y aquí solo
# están los valores ORIGINALES; si el equipo no ha editado uno, se usa el
# original. Los textos aceptan variables entre llaves, p. ej. {nombre}.
class WaAutoText
  SETTING_KEY = 'wa_auto_responses'

  # key => { label:, vars: [...], text: <original> }
  DEFAULTS = {
    'verificado' => {
      label: '✅ Cuenta verificada (respuesta al WhatsApp de verificación)',
      vars: %w[nombre tienda],
      text: "¡Verificado! Tu cuenta acasa ya está activa. Bienvenid@ {nombre}. " \
            "Por aquí podrás dar seguimiento a tus pedidos.\n\n" \
            '🛒 Empieza a comprar para tu familia en México: {tienda}'
    },
    'aprobada' => {
      label: '🎉 Cuenta aprobada (al aprobar la orden en Órdenes)',
      vars: %w[nombre],
      text: '¡Felicidades, {nombre}! 🎉 Tu cuenta Ácasa fue APROBADA. ' \
            'El siguiente paso es tu contrato: lo generamos y te lo enviamos ' \
            'por este medio para tu firma. Cualquier duda, responde aquí mismo.'
    },
    'firma' => {
      label: '📄 Contrato listo para firma (Enviar a firma)',
      vars: %w[nombre contrato enlace],
      text: "Hola {nombre}! 🎉 Tu contrato {contrato} de acasa está listo. " \
            "Inicia sesión y fírmalo aquí: {enlace}\n\n" \
            'Hello! Your acasa contract {contrato} is ready. Please log in and sign it here: {enlace}'
    },
    'fwd_intro' => {
      label: '📨 Paquete de reenvío — introducción al cliente',
      vars: %w[nombre],
      text: '¡Ya casi, {nombre}! 🙌 Para agilizar tu aprobación, REENVÍA cada uno ' \
            'de los siguientes mensajes a la persona indicada. Ellos solo tocan el enlace y nos mandan ' \
            'el saludo — así los verificamos al instante 💪'
    },
    'fwd_referencia' => {
      label: '📨 Paquete de reenvío — mensaje para cada referencia',
      vars: %w[referencia cliente enlace],
      text: 'Hola {referencia}! Soy {cliente}. Estoy abriendo mi cuenta de crédito en Ácasa ' \
            'y te puse como referencia 🙏 ¿Me ayudas con una verificación rápida? ' \
            'Solo toca aquí y mándales un saludo: {enlace}'
    },
    'fwd_domicilio' => {
      label: '📨 Paquete de reenvío — mensaje para el contacto de domicilio',
      vars: %w[referencia cliente enlace],
      text: 'Hola {referencia}! Soy {cliente}. Estoy abriendo mi cuenta de crédito en Ácasa ' \
            'y te puse como mi contacto de domicilio 🙏 ¿Me ayudas con una verificación rápida? ' \
            'Solo toca aquí y mándales un saludo: {enlace}'
    },
    'fwd_trabajo' => {
      label: '📨 Paquete de reenvío — mensaje para el trabajo',
      vars: %w[cliente enlace],
      text: 'Hola! Soy {cliente}. Ácasa necesita una verificación rápida de mi empleo 🙏 ¿Me apoyas? ' \
            'Solo toca aquí y mándales un saludo: {enlace}'
    },
    'ent_apertura' => {
      label: '🎤 Entrevista — apertura (cuando la referencia nos escribe)',
      vars: %w[referencia cliente rol],
      text: 'Hola {referencia}, te contacto de Ácasa porque {cliente} te nombró {rol} ' \
            'para validar un crédito. Son solo 4 preguntas y todas se contestan con UN toque. ¿Empezamos?'
    },
    'ent_gracias' => {
      label: '🎤 Entrevista — cierre (gracias; lleva botón a la tienda)',
      vars: [],
      text: '¡Listo, mil gracias por tu ayuda! 🙌 Eso era todo. Y si a ti también te gustaría ' \
            'estrenar con crédito Ácasa, échanos un ojo:'
    },
    'ent_despues' => {
      label: '🎤 Entrevista — pidió que le escribamos más tarde',
      vars: [],
      text: 'Sin problema 🙏 Te escribimos más tarde. ¡Que tengas excelente día!'
    },
    'ent_flag' => {
      label: '🎤 Entrevista — cierre cuando dice NO conocer al cliente',
      vars: [],
      text: 'Entendido, muchas gracias por tu tiempo 🙏 ¡Que tengas buen día!'
    },
    'soporte_recibido' => {
      label: '🆘 Soporte — acuse al ABRIR el ticket',
      vars: %w[nombre ticket],
      text: '¡Recibido, {nombre}! 🙏 Abrimos tu solicitud de ayuda (ticket {ticket}). ' \
            'Una persona de nuestro equipo te responde por aquí en breve.'
    },
    'soporte_resuelto' => {
      label: '🆘 Soporte — aviso al RESOLVER el ticket',
      vars: %w[nombre ticket resolucion],
      text: '¡Listo, {nombre}! ✅ Tu solicitud {ticket} quedó resuelta: {resolucion}. ' \
            'Si necesitas algo más, escríbenos por aquí con confianza 🙌'
    }
  }.freeze

  class << self
    def saved
      JSON.parse(AppSetting.get(SETTING_KEY).to_s)
    rescue StandardError
      {}
    end

    def save!(hash)
      clean = (hash || {}).slice(*DEFAULTS.keys).transform_values { |v| v.to_s[0, 2000] }
      AppSetting.set(SETTING_KEY, clean.to_json)
    end

    # Texto vigente (editado o el original).
    def text(key)
      saved[key.to_s].presence || DEFAULTS.dig(key.to_s, :text).to_s
    end

    # Rellena {variables}. Las variables no provistas quedan vacías.
    def render(key, vars = {})
      t = text(key)
      vars.each { |k, v| t = t.gsub("{#{k}}", v.to_s) }
      t.gsub(/\{[a-z_]+\}/, '')
    end

    # Para la pantalla de Configuración.
    def all
      s = saved
      DEFAULTS.map do |k, d|
        { key: k, label: d[:label], vars: d[:vars], original: d[:text],
          text: s[k].presence || d[:text], edited: s[k].present? }
      end
    end
  end
end
