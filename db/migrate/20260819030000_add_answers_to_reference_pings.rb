# frozen_string_literal: true

# Entrevista de verificación: transcripción de respuestas (JSON) y el índice de
# la pregunta en curso — una pregunta a la vez, sin abrumar por WhatsApp.
class AddAnswersToReferencePings < ActiveRecord::Migration[7.1]
  def change
    add_column :reference_pings, :answers, :text unless column_exists?(:reference_pings, :answers)
    add_column :reference_pings, :question_idx, :integer, default: 0 unless column_exists?(:reference_pings, :question_idx)
  end
end
