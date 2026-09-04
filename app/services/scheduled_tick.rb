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
    # 3.5) MOTOR DE DECISIÓN del gate de referencias (1 pm Monterrey, 1x/día):
    #    re-evalúa TODO el libro madurado; si algún veredicto o la recomendación
    #    cambian, queda en la Bitácora y en el banner del Motor de Riesgo.
    if t.hour == 13 && defined?(ReferenceGateReadiness) && defined?(ReferenceGate) && ReferenceGate.ready?
      begin
        key = "rg_findings_#{t.to_date}"
        unless Rails.cache.read(key)
          Rails.cache.write(key, 1, expires_in: 20.hours)
          out[:reference_gate_findings] = ReferenceGateReadiness.evaluate!['recomendacion']
        end
      rescue StandardError => e
        out[:reference_gate_findings] = e.message
      end
    end

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

    # 4) RONDA DEL CATÁLOGO: APAGADA por decisión de negocio — la verificación
    #    con Rainforest se hace UNA sola vez al scrapear (1 crédito por artículo)
    #    y Amazon bloquea las consultas gratuitas desde el servidor. El servicio
    #    CatalogPatrol queda listo por si algún día se quiere reactivar.
    # begin
    #   out[:catalog_patrol] = CatalogPatrol.run! if defined?(CatalogPatrol)
    # rescue StandardError => e
    #   out[:catalog_patrol] = e.message
    # end

    # 5) CIERRE CONTABLE (gratis, pura base de datos): corte DIARIO justo después
    #    de medianoche (Monterrey) con el día anterior completo; corte MENSUAL el
    #    día 1 con el mes anterior + paquete CSV al contador (si hay correo
    #    configurado en Contabilidad). Idempotente: si el corte ya existe, no se toca.
    if t.hour.zero? && defined?(AccountingClose) && AccountingClose.table_exists?
      begin
        y = t.to_date - 1
        existed = AccountingClose.exists?(period_type: 'daily', period_date: y)
        AccountingClose.run_daily!(y)
        out[:eod] = existed ? 'ya existía' : "corte #{y}"
        if t.day == 1
          m = t.to_date.prev_month.beginning_of_month
          existed_m = AccountingClose.exists?(period_type: 'monthly', period_date: m)
          AccountingClose.run_monthly!(m)
          out[:eom] = existed_m ? 'ya existía' : "corte mensual #{m.strftime('%Y-%m')}"
          if !existed_m && AppSetting.get('accounting_email').to_s.present?
            AccountingMailer.monthly_package(m).deliver_now
            out[:eom_mail] = 'paquete enviado'
          end
        end
      rescue StandardError => e
        out[:eod] = e.message
        WaAlert.notify('Corte contable automático', e.message) if defined?(WaAlert)
      end
    end

    Rails.logger.info "[ScheduledTick] #{out.inspect}"
    puts out.inspect
    out
  end
end
