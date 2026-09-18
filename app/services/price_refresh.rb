# frozen_string_literal: true

# REFRESCO DE PRECIOS Y PROMOCIONES (automático).
#
# Consulta Amazon vía Rainforest (1 crédito por artículo, gratis si está en
# caché <6 h) y deja el producto al día:
#   · precio en pesos y su conversión a dólares con el tipo de cambio de hoy
#   · el "Desde $X /sem" recalculado
#   · vendido / entregado por Amazon
#   · LA PROMOCIÓN: si Amazon sigue enseñando precio de lista arriba del precio
#     de venta, se guarda el descuento; si ya NO hay oferta, el artículo REGRESA
#     SOLO a precio normal (promo = false) y se sale de la vista 0.
#
# Lo usa ScheduledTick: los artículos en promoción se revisan TODOS LOS DÍAS
# (las ofertas se acaban rápido) y el catálogo completo una vez por semana.
class PriceRefresh
  DAILY_KEY = 'price_refresh_promos_last'
  WEEKLY_KEY = 'price_refresh_all_last'

  class << self
    # Solo los que están en promoción (barato: son pocos).
    def run_promos!(limit: 300)
      scope = Product.where(status: 'active').where(promo: true).where.not(asin: [nil, ''])
      run_batch!(scope.limit(limit), motivo: 'promos')
    end

    # Todo el catálogo activo (la pasada semanal).
    def run_all!(limit: 2000)
      scope = Product.where(status: 'active').where.not(asin: [nil, '']).order(:id)
      run_batch!(scope.limit(limit), motivo: 'catálogo completo')
    end

    def run_batch!(scope, motivo: '')
      svc = RainforestImportService.new
      return { omitido: 'sin API key de Rainforest' } unless svc.configured?

      rate = ExchangeRate.current_rate.to_f
      return { omitido: 'sin tipo de cambio' } if rate <= 0

      res = { motivo: motivo, revisados: 0, precio_cambiado: 0, promos_nuevas: 0, promos_terminadas: 0, sin_datos: 0 }
      scope.find_each do |p|
        begin
          r = refresh_one!(p, svc: svc, rate: rate)
          res[:revisados] += 1
          res[:precio_cambiado] += 1 if r[:price_changed]
          res[:promos_nuevas] += 1 if r[:promo_started]
          res[:promos_terminadas] += 1 if r[:promo_ended]
          res[:sin_datos] += 1 if r[:no_data]
        rescue StandardError => e
          res[:sin_datos] += 1
          Rails.logger.warn "[PriceRefresh] #{p.asin}: #{e.message}"
        end
        sleep 0.2 # no atropellar a Rainforest
      end
      Rails.logger.info "[PriceRefresh] #{res.inspect}"
      res
    end

    # Un artículo. Devuelve qué cambió.
    def refresh_one!(product, svc: nil, rate: nil)
      svc ||= RainforestImportService.new
      rate = rate.presence || ExchangeRate.current_rate.to_f
      return { no_data: true } if product.asin.blank? || rate <= 0

      detail = svc.send(:fetch_product_detail, product.asin, domain_for(product))
      return { no_data: true } if detail.blank?

      buybox = detail['buybox_winner'] || {}
      price = buybox['price'] || {}
      value = price['value']
      return { no_data: true } if value.blank?

      en_pesos = price['currency'].to_s.casecmp('mxn').zero?
      usd = en_pesos ? (value.to_f / rate).round(2) : value.to_f.round(2)
      antes = product.price.to_f

      product.update!(
        original_price: (en_pesos ? value.to_f.round(2) : product.original_price),
        price: usd
      )
      product.update_column(:min_weekly_payment, product.recalculated_min_weekly_payment)

      estaba = product.promo?
      sigue = apply_offer!(product, detail, value.to_f)

      { price_changed: (antes.round(2) != usd),
        promo_started: (!estaba && sigue),
        promo_ended: (estaba && !sigue) }
    end

    # ¿Amazon sigue enseñando una oferta? El precio de lista del artículo viene
    # en buybox_winner.rrp (recommended retail price); si está por encima del
    # precio de venta, eso es el descuento que ve el cliente. deal (ofertas
    # relámpago) manda la etiqueta cuando existe.
    def apply_offer!(product, detail, sale_value)
      buybox = detail['buybox_winner'] || {}
      lista = (buybox['rrp'] || {})['value'].to_f
      ahorro = (buybox['save'] || {})['value'].to_f
      lista = (sale_value + ahorro) if lista <= 0 && ahorro.positive?

      pct = (lista > sale_value && lista.positive?) ? (((lista - sale_value) / lista) * 100).round : 0
      deal = detail['deal'].is_a?(Hash) ? detail['deal'] : nil
      etiqueta = deal && (deal['badge'] || deal['type'] || (deal['is_lightning_deal'] ? 'Oferta relámpago' : nil))

      if pct >= Product::PROMO_MIN_PCT
        product.apply_promo!(list_price: lista, percent_off: pct, badge: etiqueta || product.promo_badge)
        true
      else
        product.clear_promo!
        false
      end
    end

    # El mercado del artículo se deduce de su moneda (igual que refresh_price).
    def domain_for(product)
      product.currency.to_s.casecmp('usd').zero? ? 'amazon.com' : 'amazon.com.mx'
    end
  end
end
