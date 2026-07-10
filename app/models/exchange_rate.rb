class ExchangeRate < ApplicationRecord
  validates :usd_to_mxn, presence: true, numericality: { greater_than: 0 }

  def self.current_rate
    order(created_at: :desc).first&.usd_to_mxn || 0
  end
end
