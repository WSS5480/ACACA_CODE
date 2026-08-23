# frozen_string_literal: true

# REPRECIACIÓN DIARIA POR TIPO DE CAMBIO (peso -> dólar).
#
# 1) CATÁLOGO COMPLETO: cada producto guarda su precio ORIGINAL en pesos
#    (original_price, MXN). Con el tipo de cambio del día se recalcula el
#    precio en dólares con UNA sola sentencia SQL — da igual si son 34 SKUs
#    o 50,000: la base de datos lo hace en milisegundos. Después se
#    actualiza el "Desde $X /sem" de cada producto por lotes.
#
# 2) PEDIDOS SIN PAGO INICIAL: mientras el cliente NO haya hecho su pago
#    inicial, su pedido se reprecia al tipo de cambio del día (total,
#    enganche proporcional, financiado, pago semanal y calendario). El
#    crédito apartado se ajusta por la diferencia, respetando el CANDADO:
#    lo financiado nunca excede el crédito del cliente (el excedente se va
#    al enganche). En cuanto existe CUALQUIER pago, el precio queda
#    CONGELADO y este proceso no lo toca.
#
# Corre una vez al día desde ScheduledTick (después de refrescar el tipo de
# cambio) y también al usar "Actualizar" en el admin. Es idempotente: si el
# tipo de cambio no cambió, no modifica nada.
class FxReprice
  def self.run!
    rate = ExchangeRate.current_rate.to_f
    return { omitido: 'sin tipo de cambio válido' } if rate <= 0

    out = { tipo_de_cambio: rate }

    # ---- 1) Catálogo: una sola sentencia para TODOS los SKUs en MXN. ----
    # price_with_discount se escala en la MISMA proporción (usa los valores
    # viejos de la fila, comportamiento estándar de UPDATE en Postgres).
    scope = Product.where("currency ILIKE 'mxn'").where('original_price > 0')
    out[:productos] = scope.update_all([
      'price_with_discount = CASE WHEN price_with_discount IS NOT NULL AND price > 0 ' \
      'THEN ROUND((price_with_discount * (original_price / ?) / price)::numeric, 2) ' \
      'ELSE price_with_discount END, ' \
      'price = ROUND((original_price / ?)::numeric, 2), ' \
      'updated_at = NOW()',
      rate, rate
    ])

    # ---- 1b) "Desde $X /sem" del catálogo (por lotes; miles de SKUs ok). ----
    desde = 0
    scope.find_each(batch_size: 500) do |p|
      mp = p.recalculated_min_weekly_payment
      if mp.to_f.positive? && (p.min_weekly_payment.to_f - mp.to_f).abs >= 0.01
        p.update_column(:min_weekly_payment, mp)
        desde += 1
      end
    end
    out[:desde_actualizados] = desde

    # ---- 2) Pedidos SIN pago inicial: repreciar al tipo de cambio del día. ----
    repreciados = 0
    Contract.where(status: 'active').where('financed_amount > 0').find_each do |c|
      next if c.payments.exists? # ya pagó algo: precio CONGELADO

      products = c.orders.filter_map(&:product)
      next if products.empty?

      new_total = products.sum(&:total_price).round(2)
      old_total = c.total_amount.to_f
      next if old_total <= 0 || (new_total - old_total).abs < 0.01

      factor       = new_total / old_total
      new_down     = (c.downpayment.to_f * factor).round(2)
      new_financed = ((new_total - new_down) * Product.finance_factor).round(2)

      user = c.user
      ActiveRecord::Base.transaction do
        if user&.credit
          # Margen = crédito disponible + lo que ESTE contrato ya tiene apartado.
          headroom = (user.credit.amount.to_f + c.financed_amount.to_f).round(2)
          if new_financed > headroom
            # CANDADO: lo que no quepa en el crédito se suma al enganche.
            new_down     = [(new_total - (headroom / Product.finance_factor)).round(2), new_down].max
            new_down     = [new_down, new_total].min
            new_financed = ((new_total - new_down) * Product.finance_factor).round(2)
          end
          delta = (new_financed - c.financed_amount.to_f).round(2)
          user.credit.update!(amount: (user.credit.amount.to_f - delta).round(2)) if delta.abs >= 0.01
        end

        weekly = c.weeks.to_i.positive? ? (new_financed / c.weeks).round(2) : c.weekly_payment
        c.update!(total_amount: new_total, downpayment: new_down,
                  financed_amount: new_financed, weekly_payment: weekly)
        c.build_amortization!
      end
      repreciados += 1
    rescue StandardError => e
      Rails.logger.error "[fx_reprice] contrato #{c.id}: #{e.message}"
      WaAlert.notify("Repreciación FX del pedido #{c.order_ref rescue c.id}", e.message) if defined?(WaAlert)
    end
    out[:pedidos_repreciados] = repreciados

    Rails.logger.info "[fx_reprice] #{out.inspect}"
    out
  end
end
