class Referral < ApplicationRecord
  belongs_to :order

  validates :order, :name, :last_name, :phone, presence: true
  validates :nationality, inclusion: { in: %w[mexican american], message: 'debe ser mexican o american' }, allow_nil: true
end
