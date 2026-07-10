require 'rails_helper'

RSpec.describe ExchangeRate, type: :model do
  describe 'validations' do
    it 'requires usd_to_mxn to be present and greater than 0' do
      expect(build(:exchange_rate, usd_to_mxn: nil)).not_to be_valid
      expect(build(:exchange_rate, usd_to_mxn: 0)).not_to be_valid
      expect(build(:exchange_rate, usd_to_mxn: -1)).not_to be_valid
      expect(build(:exchange_rate, usd_to_mxn: 18.5)).to be_valid
    end
  end

  describe '.current_rate' do
    it 'returns 0 when there are no records' do
      expect(ExchangeRate.current_rate).to eq(0)
    end

    it 'returns the most recently created rate' do
      create(:exchange_rate, usd_to_mxn: 18.0, created_at: 2.days.ago)
      create(:exchange_rate, usd_to_mxn: 19.5, created_at: 1.day.ago)
      expect(ExchangeRate.current_rate).to eq(19.5)
    end
  end
end
