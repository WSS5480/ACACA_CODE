# frozen_string_literal: true

module Api
  # TICK programado (sustituye al worker de Sidekiq para tareas recurrentes):
  # un Cron Job lo llama cada 15 minutos y ScheduledTick corre lo que toque
  # (verificaciones de referencias, recordatorios de compromisos, tipo de cambio).
  # Protegido con TICK_SECRET (o AUTOPAY_SECRET como respaldo).
  class TicksController < ApplicationController
    include TokenAuthenticatable
    skip_before_action :authenticate_entity!, raise: false

    # POST /api/ticks/run   (header X-Tick-Token)
    def run
      secret = ENV['TICK_SECRET'].presence || ENV['AUTOPAY_SECRET'].presence
      provided = request.headers['X-Tick-Token'].to_s
      unless secret.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)
        return render(json: { error: 'No autorizado' }, status: :forbidden)
      end

      render json: { ok: true, ran: ScheduledTick.run }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
