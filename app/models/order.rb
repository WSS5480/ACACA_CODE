class Order < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :product, optional: true
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

  private

  def refund_credit_to_user
    return if %w[incomplete paid].include?(status)
    return unless user&.credit.present? && used_credit.to_d > 0

    user.credit.update!(amount: user.credit.amount + used_credit)
  end
end
