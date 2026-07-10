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

    images.map { |image| rails_blob_url(image) }
  end

  # Retorna el precio efectivo del producto:
  # - price_with_discount si está definido y es mayor a 0
  # - price en caso contrario
  def effective_price
    price_with_discount.present? && price_with_discount > 0 ? price_with_discount : price
  end

  def calculate_weekly_payment(weeks:, downpayment:, product_cost_usd: nil, used_credit: 0, turns: nil, decimal_factor: nil)
    product_cost_usd ||= effective_price
    turns ||= self.turns
    decimal_factor ||= self.decimal_factor
    weeks ||= 52
    return 0 if product_cost_usd.blank?
    differential = product_cost_usd - used_credit
    cash_price = product_cost_usd * turns * decimal_factor
    downpayment ||= 0.1 * cash_price
    #down_plus_diff = downpayment + differential # presente en los cálculos de acasa pero no es usado aquí
    financed_amount = (product_cost_usd * turns) - downpayment - differential
    weekly_no_waiver = financed_amount / weeks.to_f
    waiver = weekly_no_waiver * 0.1
    weekly_payment = weekly_no_waiver + waiver
    weekly_payment.round(2)
  end
end

