# frozen_string_literal: true

# Crea la plantilla 'cuenta_aprobada' en Meta (una sola vez).
# Uso (Render Shell): bin/rails runner scripts/tpl_aprobada.rb
body = '¡Felicidades, {{1}}! 🎉 Tu cuenta Ácasa fue APROBADA. ' \
       'El siguiente paso es tu contrato: lo generamos y te lo enviamos ' \
       'por WhatsApp para tu firma.'
begin
  r = WhatsappCloud.new.create_template(
    name: 'cuenta_aprobada', category: 'UTILITY', language: 'es_MX',
    body: body, examples: ['Daniela']
  )
  puts "CREADA: #{r.inspect}"
rescue StandardError => e
  puts "ERROR: #{e.message}"
end
