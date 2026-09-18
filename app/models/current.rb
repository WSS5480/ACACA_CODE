# frozen_string_literal: true

# Memoria de UNA sola petición. Rails la limpia sola al terminar cada request
# (y cada job), así que lo que se guarde aquí no se queda pegado entre usuarios.
#
# settings: caché de AppSetting durante la petición. Sin esto, pintar el
# catálogo leía la tasa de interés, el factor de contado y los pisos de enganche
# de la base de datos DECENAS de veces por producto — miles de consultas para
# una sola pantalla.
class Current < ActiveSupport::CurrentAttributes
  attribute :settings
end
