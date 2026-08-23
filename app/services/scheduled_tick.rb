# frozen_string_literal: true

# TICK programado: lo ejecuta un Cron Job de Render cada 15 minutos
# (bundle exec rails runner ScheduledTick.run). Sustituye al worker de Sidekiq
# para las tareas RECURRENTES — cada tarea es idempotente, así que correr de
# más nunca duplica envíos.
class ScheduledTick
  def self.run
    out = {}

    # 1) Verificación de referencias: el envío AUTOMÁTICO de plantillas está
    #    APAGADO a propósito — el "paquete de reenvío" hace que las referencias
    #    nos escriban ELLAS (ventana abierta, conversación libre). Las plantillas
    #    ref_* quedan solo para contacto MANUAL desde el selector 📋 cuando una
    #    referencia nunca responde. La cola reference_pings sigue registrando a
    #    quién falta verificar.
    # if defined?(ReferencePing) && ReferencePing.table_exists?
    #   out[:reference_pings] = ReferencePing.run_due!
    # end

    # 2) Recordatorio del día ANTERIOR de cada compromiso de pago:
    #    se dispara en la mañana de Monterrey (9-10 am); reminded_at evita duplicados.
    t = Time.now.in_time_zone('America/Monterrey')
    if t.hour == 9 && defined?(PaymentCommitment) && PaymentCommitment.table_exists?
      begin
        out[:commitment_reminders] = PaymentCommitment.run_reminders!
      rescue StandardError => e
        out[:commitment_reminders] = e.message
        WaAlert.notify('Recordatorios de compromisos de pago', e.message) if defined?(WaAlert)
      end
    end

    # 3) Tipo de cambio USD->MXN una vez al día (mediodía de Monterrey) y
    #    REPRECIACIÓN del catálogo completo + pedidos sin pago inicial.
    if t.hour == 12 && defined?(ExchangeRates::FetchRateJob)
      begin
        ExchangeRates::FetchRateJob.new.perform
        out[:exchange_rate] = 'ok'
      rescue StandardError => e
        out[:exchange_rate] = e.message
      end
      begin
        out[:fx_reprice] = FxReprice.run! if defined?(FxReprice)
      rescue StandardError => e
        out[:fx_reprice] = e.message
        WaAlert.notify('Repreciación diaria por tipo de cambio', e.message) if defined?(WaAlert)
      end
    end

    Rails.logger.info "[ScheduledTick] #{out.inspect}"
    puts out.inspect
    out
  end
end
