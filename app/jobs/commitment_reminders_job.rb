# frozen_string_literal: true

# Recordatorio AUTOMÁTICO del día anterior a cada compromiso de pago.
# Corre todos los días (ver config/sidekiq_schedule.yml).
class CommitmentRemindersJob < ApplicationJob
  queue_as :notifications

  def perform(date = nil)
    return unless defined?(PaymentCommitment) && PaymentCommitment.table_exists?

    target = date ? Date.parse(date.to_s) : (Date.current + 1)
    result = PaymentCommitment.run_reminders!(for_date: target)
    Rails.logger.info "[CommitmentRemindersJob] #{result.inspect}"
    result
  rescue StandardError => e
    Rails.logger.error "[CommitmentRemindersJob] #{e.class}: #{e.message}"
    nil
  end
end
