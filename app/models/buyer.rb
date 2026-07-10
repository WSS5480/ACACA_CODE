class Buyer < ApplicationRecord
  belongs_to :order

  has_one_attached :identification
  has_one_attached :proof_of_address
  has_one_attached :proof_of_income

  validates :order, :name, :last_name, :phone, :email, presence: true
  validates :nationality, inclusion: { in: %w[mexican american canadian other], message: 'debe ser mexican, american, canadian o other' }, allow_nil: true
  validates :housing_type, inclusion: { in: %w[owner tenant], message: 'debe ser owner o tenant' }, allow_nil: true
end
