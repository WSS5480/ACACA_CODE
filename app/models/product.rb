class Product < ApplicationRecord
  include Rails.application.routes.url_helpers

  has_many :product_categories, dependent: :destroy
  has_many :categories, through: :product_categories
  has_one :specifications_list, dependent: :destroy
  has_many :orders, dependent: :nullify
  has_many_attached :images

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def image_urls
    return [] unless images.attached?

    # Rutas RELATIVAS en desarrollo: así las fotos cargan por el MISMO origen que
    # sirve la página (shop.html vía el túnel de Cloudflare -> tu colega las ve).
    # En producción se generan URLs absolutas (S3 / host configurado).
    # URLs absolutas en todos los entornos: el front en :3001 (u otro origen) puede cargar las fotos.
    images.map { |image| rails_blob_url(image) }
  rescue StandardError => e
    Rails.logger.warn("[product #{id}] no se pudo generar image_urls: #{e.message}")
    []
  end

  def effective_price
    price_with_discount.present? && price_with_discount > 0 ? price_with_discount : price
  end

  # ---- PROMOCIONES Y ORDEN DEL CATÁLOGO ----------------------------------
  # Un artículo en promoción cuenta como VISTA 0 (va primero) sin perder la
  # vista que el equipo le puso: cuando la oferta se acaba vuelve a su lugar.
  VIEW_MIN = 1
  VIEW_MAX = 6
  PROMO_VIEW = 0
  PROMO_MIN_PCT = 3 # menos de esto no es oferta, es redondeo

  def promo?
    has_attribute?(:promo) ? !!self[:promo] : false
  end

  def effective_view
    return PROMO_VIEW if promo?

    v = respond_to?(:catalog_view) ? catalog_view.to_i : VIEW_MIN
    v.between?(VIEW_MIN, VIEW_MAX) ? v : VIEW_MIN
  end

  # Precio de lista EN DÓLARES para tachar en la tienda. Se deriva del % de
  # descuento y no del tipo de cambio, así siempre cuadra con el precio que se
  # está mostrando (aunque el catálogo se repreció por tipo de cambio).
  def promo_list_price_usd
    return nil unless promo?

    pct = promo_percent_off.to_f
    base = effective_price.to_f
    return nil unless pct.positive? && pct < 100 && base.positive?

    (base / (1 - (pct / 100.0))).round(2)
  end

  def apply_promo!(list_price: nil, percent_off: nil, badge: nil)
    pct = percent_off.to_f.round
    return clear_promo! if pct < PROMO_MIN_PCT

    update_columns(
      promo: true,
      promo_list_price: (list_price.presence && list_price.to_f.round(2)),
      promo_percent_off: pct,
      promo_badge: badge.presence&.to_s&.slice(0, 120),
      promo_checked_at: Time.current
    )
    true
  end

  def clear_promo!
    return false unless promo?

    update_columns(promo: false, promo_list_price: nil, promo_percent_off: nil,
                   promo_badge: nil, promo_checked_at: Time.current)
    false
  end

  # Orden del catálogo: promos primero, luego por vista y por el orden que el
  # equipo le dio dentro de la vista.
  scope :catalog_ordered, lambda {
    order(Arel.sql('CASE WHEN products.promo THEN 0 ELSE products.catalog_view END ASC, products.catalog_order ASC, products.id ASC'))
  }
  scope :in_promo, -> { where(promo: true) }

  TERMS = { 52 => 12, 39 => 9, 26 => 6, 13 => 3 }.freeze  # semanas => meses (12/9/6/3)
  MIN_WEEKLY = 20                                          # pago semanal minimo estandar

  # Minimo semanal por plazo: 3 meses o menos (<=13 sem) puede bajar a $10/sem; mayor plazo $20/sem.
  def self.min_weekly_for(weeks)
    weeks.to_i <= 13 ? 10 : 20
  end

  # PRECIO DE CONTADO (cash price) = costo x turns x factor. Base de enganche y financiamiento.
  def total_price
    return 0 if effective_price.blank?
    (effective_price.to_f * (turns || 3.5).to_f * (decimal_factor || Product.default_cash_factor).to_f).round(2)
  end

  # TOTAL (precio a credito de referencia) = costo x turns (sin factor).
  def full_price
    return 0 if effective_price.blank?
    (effective_price.to_f * (turns || 3.5).to_f).round(2)
  end

  # Enganche mínimo = piso por CATEGORÍA (10% base; configurable por tipo de
  # artículo en Seguridad → Tasas e impuestos → Enganche mínimo por categoría).
  def min_downpayment
    pct = defined?(CategoryFloor) ? CategoryFloor.pct_for(self) : 10.0
    (total_price * pct / 100.0).round(2)
  end

  # Pago semanal: financiado = (contado - enganche) x factor de financiamiento.
  # El factor sale de la TASA DE INTERÉS configurable (Seguridad → Tasas e impuestos):
  # factor = 1 + tasa/100 (25% → 1.25). El factor de contado es su inverso: 100/(100+tasa).
  FINANCE_FACTOR = 1.25 # respaldo si no hay configuración

  def self.interest_rate
    AppSetting.rate('interest_rate', 25.0)
  rescue StandardError
    25.0
  end

  def self.finance_factor
    (1 + interest_rate / 100.0).round(4)
  end

  def self.default_cash_factor
    (100.0 / (100.0 + interest_rate)).round(4)
  end

  def self.tax_rate
    AppSetting.rate('tax_rate', 0.0)
  rescue StandardError
    0.0
  end

  def self.waiver_rate
    AppSetting.rate('waiver_rate', 10.0)
  rescue StandardError
    10.0
  end

  # Tasa de interés MORATORIO anual (%): se acumula sobre pagos vencidos
  # después de 1 día de atraso (tasa/360 por día, cláusula TERCERA del contrato).
  def self.mora_rate
    AppSetting.rate('mora_rate', 0.0)
  rescue StandardError
    0.0
  end

  # Cuota de procesamiento (USD, fija): se cobra con el pago inicial (cláusula TERCERA).
  def self.processing_fee
    AppSetting.rate('processing_fee', 0.0)
  rescue StandardError
    0.0
  end

  # TOPE de pago/ingreso (pti, %): 0 = APAGADO. Si está activo, el pago
  # semanal nuevo + lo que ya paga en contratos activos no puede rebasar este
  # % del ingreso semanal declarado.
  def self.pti_max
    AppSetting.rate('pti_max', 0.0)
  rescue StandardError
    0.0
  end

  # Tope MÁS APRETADO para expedientes que el gate marcó con ingreso variable.
  def self.pti_max_variable
    AppSetting.rate('pti_max_variable', 0.0)
  rescue StandardError
    0.0
  end

  # CAT informativo (%): sólo para la carátula del contrato.
  def self.cat_rate
    AppSetting.rate('cat_rate', 0.0)
  rescue StandardError
    0.0
  end

  def calculate_weekly_payment(weeks:, downpayment: nil, product_cost_usd: nil, used_credit: 0, turns: nil, decimal_factor: nil)
    cost = (product_cost_usd || effective_price).to_f
    t = (turns || self.turns || 3.5).to_f
    f = (decimal_factor || self.decimal_factor || Product.default_cash_factor).to_f
    return 0 if cost <= 0 || weeks.to_f <= 0
    cash = cost * t * f
    dp = (downpayment || cash * 0.10).to_f
    principal = (cash - dp).round(2)
    return 0 if principal <= 0
    Product.weekly_annuity(principal, weeks.to_i)
  end

  # Pago SEMANAL amortizado sobre SALDO INSOLUTO — la matemática del contrato
  # (cláusula SÉPTIMA): interés = saldo × (tasa anual ÷ 360 × 7 días). Misma
  # fórmula que Contract.amortized_quote, para que tienda y contrato cuadren.
  def self.weekly_annuity(principal, weeks)
    p = principal.to_f
    n = weeks.to_i
    return 0 if p <= 0 || n <= 0
    i = (interest_rate / 100.0) * 7.0 / 360.0
    return (p / n).round(2) if i <= 0
    ((p * i) / (1 - (1 + i)**-n)).round(2)
  end

  # Plazos disponibles (solo los que superan $20 semanales) para un enganche dado
  def available_payment_plans(downpayment = nil)
    dp = downpayment || min_downpayment
    TERMS.map do |weeks, months|
      { weeks: weeks, months: months, weekly_payment: calculate_weekly_payment(weeks: weeks, downpayment: dp) }
    end.select { |p| p[:weekly_payment] > Product.min_weekly_for(p[:weeks]) }
    if plans_empty_fallback?(dp)
      fin = (total_price - dp).round(2)
      weeks_r = [(fin / 10.0).ceil, 1].max
      return [{ weeks: weeks_r, months: [(weeks_r / 4.333).round, 1].max, weekly_payment: [10.0, fin].min.round(2) }]
    end
    TERMS.map do |weeks, months|
      { weeks: weeks, months: months, weekly_payment: calculate_weekly_payment(weeks: weeks, downpayment: dp) }
    end.select { |p| p[:weekly_payment] > Product.min_weekly_for(p[:weeks]) }
  end

  def plans_empty_fallback?(dp)
    fin = (total_price - dp).round(2)
    return false if fin <= 0
    TERMS.none? { |weeks, _m| calculate_weekly_payment(weeks: weeks, downpayment: dp) > Product.min_weekly_for(weeks) }
  end

  # Refresca el "Desde $X /sem" GUARDADO de todo el catálogo (el serializer lo
  # recalcula en vivo, pero el filtro por rango usa la columna). Se llama al
  # cambiar la tasa de interés.
  def self.refresh_min_weekly!
    where(status: 'active').find_each { |p| p.update_column(:min_weekly_payment, p.recalculated_min_weekly_payment) }
  rescue StandardError => e
    Rails.logger.warn "[products] refresh_min_weekly: #{e.message}"
  end

  # "Pago x sem": el pago semanal mínimo entre los plazos ofrecidos
  def recalculated_min_weekly_payment
    plans = available_payment_plans
    plans.empty? ? 0 : plans.map { |p| p[:weekly_payment] }.min
  end
end
