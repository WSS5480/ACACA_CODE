# frozen_string_literal: true

# ENCUESTA a referencias por WhatsApp con botones: al escribirnos la referencia
# (tocando el enlace del paquete de reenvío) se le hace una mini-entrevista:
# ¿recomiendas al cliente? (Sí/No) y ¿desde hace cuánto lo conoces / vive ahí /
# trabaja ahí? Las respuestas quedan en el registro y en el historial.
class AddSurveyToReferencePings < ActiveRecord::Migration[7.1]
  def change
    add_column :reference_pings, :survey_state, :string unless column_exists?(:reference_pings, :survey_state)
    add_column :reference_pings, :recommends, :string unless column_exists?(:reference_pings, :recommends)
    add_column :reference_pings, :time_known, :string unless column_exists?(:reference_pings, :time_known)
  end
end
