# frozen_string_literal: true

# Envía las verificaciones de referencias pendientes que estén en horario
# local permitido (8am–9pm). Corre cada 15 minutos (config/sidekiq_schedule.yml).
class ReferencePingsJob < ApplicationJob
  queue_as :notifications

  def perform
    return unless defined?(ReferencePing) && ReferencePing.table_exists?

    result = ReferencePing.run_due!
    Rails.logger.info "[ReferencePingsJob] #{result.inspect}"
    result
  rescue StandardError => e
    Rails.logger.error "[ReferencePingsJob] #{e.class}: #{e.message}"
    nil
  end
end
