class Order < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :product, optional: true
  belongs_to :contract, optional: true
  belongs_to :beneficiary, optional: true
  has_one :buyer, dependent: :destroy
  has_one :guarantor, dependent: :destroy
  has_many :referrals, dependent: :destroy

  validates :user, :product, presence: true, on: :create
  validates :user_email, :product_title, :product_asin, :product_price,
            :product_turns, :product_decimal_factor, :used_credit,
            :downpayment, :weekly_payment, :credit_duration, presence: true
  validates :status, inclusion: { in: %w[pending approved incomplete paid cancelled], message: 'debe ser pending, approved, incomplete, paid o cancelled' }
  validates :hightouch_id, uniqueness: true, allow_nil: true

  before_destroy :refund_credit_to_user

  # VENTAS POR PRODUCTO para el catálogo del admin.
  #
  # Cuenta TODO pedido que no esté cancelado —pendiente, aprobado o pagado—:
  # si alguien intentó llevárselo, el producto se mueve. Devuelve el total
  # histórico, cuántos en los últimos 30/60/90 días y la fecha de la última
  # venta, en UNA sola consulta agrupada para todo el catálogo (nada de una
  # consulta por producto, que era justo lo que hacía lenta esta pantalla).
  VENTA_NO_CUENTA = %w[cancelled].freeze

  def self.sales_by_product
    return {} unless table_exists?

    filas = where.not(status: VENTA_NO_CUENTA).where.not(product_id: nil)
                 .group(:product_id)
                 .pluck(Arel.sql(<<~SQL.squish))
                   product_id,
                   COUNT(*),
                   COUNT(*) FILTER (WHERE orders.created_at >= NOW() - INTERVAL '30 days'),
                   COUNT(*) FILTER (WHERE orders.created_at >= NOW() - INTERVAL '60 days'),
                   COUNT(*) FILTER (WHERE orders.created_at >= NOW() - INTERVAL '90 days'),
                   MAX(orders.created_at)
                 SQL

    filas.each_with_object({}) do |(pid, total, d30, d60, d90, ultima), h|
      h[pid.to_i] = { total: total.to_i, d30: d30.to_i, d60: d60.to_i, d90: d90.to_i, last_at: ultima }
    end
  rescue StandardError => e
    Rails.logger.warn "[Order.sales_by_product] #{e.message}"
    {}
  end

  private

  def refund_credit_to_user
    return if %w[incomplete paid].include?(status)
    return unless user&.credit.present? && used_credit.to_d > 0

    user.credit.update!(amount: user.credit.amount + used_credit)
  end
end
