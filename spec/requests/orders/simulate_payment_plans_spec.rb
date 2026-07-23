require 'rails_helper'

RSpec.describe 'GET /api/orders/simulate_payment_plans', type: :request do
  let!(:product) { create(:product, price: 300, turns: 3.5, decimal_factor: 0.75) }

  def get_plans(params)
    get '/api/orders/simulate_payment_plans', params: params
  end

  it 'returns the four payment plans for a valid request' do
    get_plans(product_id: product.id, product_price: 300, downpayment: 300, used_credit: 0)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    plans = body['payment_plans']

    expect(plans.map { |p| p['weeks'] }).to eq([52, 34, 26, 13])
    week52 = plans.find { |p| p['weeks'] == 52 }
    expect(week52['weekly_payment']).to eq(9.52)
  end

  it 'rejects a request with missing parameters' do
    get_plans(product_id: product.id, product_price: 300)
    expect(response).to have_http_status(:bad_request)
  end

  it 'returns 404 when the product does not exist' do
    get_plans(product_id: 0, product_price: 300, downpayment: 300, used_credit: 0)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects when the price does not match the product' do
    get_plans(product_id: product.id, product_price: 250, downpayment: 250, used_credit: 0)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'accepts prices that differ only by floating-point noise' do
    get_plans(product_id: product.id, product_price: 299.999, downpayment: 299.999, used_credit: 0)
    expect(response).to have_http_status(:ok)
  end
end
