require 'rails_helper'

RSpec.describe Product, type: :model do
  describe '#effective_price' do
    it 'returns the price when there is no discount' do
      product = build(:product, price: 300, price_with_discount: nil)
      expect(product.effective_price).to eq(300)
    end

    it 'prefers price_with_discount when it is greater than 0' do
      product = build(:product, :discounted) # price 900, discount 750
      expect(product.effective_price).to eq(750)
    end

    it 'ignores a discount of 0' do
      product = build(:product, price: 300, price_with_discount: 0)
      expect(product.effective_price).to eq(300)
    end
  end

  describe '#calculate_weekly_payment' do
    let(:product) { build(:product, price: 300, turns: 3.5, decimal_factor: 0.75) }

    it 'computes the four standard terms for a full downpayment, no credit' do
      expect(product.calculate_weekly_payment(weeks: 52, downpayment: 300, product_cost_usd: 300, used_credit: 0)).to eq(9.52)
      expect(product.calculate_weekly_payment(weeks: 34, downpayment: 300, product_cost_usd: 300, used_credit: 0)).to eq(14.56)
      expect(product.calculate_weekly_payment(weeks: 26, downpayment: 300, product_cost_usd: 300, used_credit: 0)).to eq(19.04)
      expect(product.calculate_weekly_payment(weeks: 13, downpayment: 300, product_cost_usd: 300, used_credit: 0)).to eq(38.08)
    end

    it 'defaults weeks to 52 when nil' do
      explicit = product.calculate_weekly_payment(weeks: 52, downpayment: 300, product_cost_usd: 300, used_credit: 0)
      defaulted = product.calculate_weekly_payment(weeks: nil, downpayment: 300, product_cost_usd: 300, used_credit: 0)
      expect(defaulted).to eq(explicit)
    end

    # NOTE (flagged for Acasa review): under the enforced rule downpayment + used_credit == price,
    # the current formula makes the financed amount = price*turns - 2*downpayment, so applying
    # STORE CREDIT (which lowers the downpayment) INCREASES the weekly payment. This test documents
    # the CURRENT behavior; it is not an endorsement of it. Change the formula only after confirming
    # the intended math with the business.
    it 'currently increases the weekly payment when store credit replaces downpayment' do
      no_credit   = product.calculate_weekly_payment(weeks: 52, downpayment: 300, product_cost_usd: 300, used_credit: 0)
      with_credit = product.calculate_weekly_payment(weeks: 52, downpayment: 200, product_cost_usd: 300, used_credit: 100)
      expect(no_credit).to eq(9.52)
      expect(with_credit).to eq(13.75)
      expect(with_credit).to be > no_credit
    end

    it 'returns 0 when the product cost is blank' do
      expect(product.calculate_weekly_payment(weeks: 52, downpayment: 0, product_cost_usd: nil, used_credit: 0)).to eq(0)
    end
  end
end
