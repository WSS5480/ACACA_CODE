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

  TERMS = { 52 => 12, 39 => 9, 26 => 6, 13 => 3 }.freeze  # semanas => meses (12/9/6/3)
  MIN_WEEKLY = 20                                          # solo se ofrecen plazos cuyo pago semanal supera $20

  # "Total" / Precio (constante) = costo x turns x factor
  def total_price
    return 0 if effective_price.blank?
    (effective_price.to_f * (turns || 3.5).to_f * (decimal_factor || 0.75).to_f).round(2)
  end

  # Enganche mínimo = 10% del total
  def min_downpayment
    (total_price * 0.10).round(2)
  end

  # Pago semanal = (Total - enganche) / semanas. Sin waiver.
  def calculate_weekly_payment(weeks:, downpayment: nil, product_cost_usd: nil, used_credit: 0, turns: nil, decimal_factor: nil)
    cost = (product_cost_usd || effective_price).to_f
    t = (turns || self.turns || 3.5).to_f
    f = (decimal_factor || self.decimal_factor || 0.75).to_f
    return 0 if cost <= 0 || weeks.to_f <= 0
    total = cost * t * f
    dp = (downpayment || total * 0.10).to_f
    ((total - dp) / weeks.to_f).round(2)
  end

  # Plazos disponibles (solo los que superan $20 semanales) para un enganche dado
  def available_payment_plans(downpayment = nil)
    dp = downpayment || min_downpayment
    TERMS.map do |weeks, months|
      { weeks: weeks, months: months, weekly_payment: calculate_weekly_payment(weeks: weeks, downpayment: dp) }
    end.select { |p| p[:weekly_payment] > MIN_WEEKLY }
  end

  # "Pago x sem": el pago semanal mínimo entre los plazos ofrecidos
  def recalculated_min_weekly_payment
    plans = available_payment_plans
    plans.empty? ? 0 : plans.map { |p| p[:weekly_payment] }.min
  end
end
