require 'rails_helper'

RSpec.describe ExchangeRates::FetchRateJob, type: :job do
  let(:api_url) { 'https://open.er-api.com/v6/latest/USD' }

  def stub_api(mxn:, status: 200)
    body = { 'result' => 'success', 'base_code' => 'USD', 'rates' => { 'MXN' => mxn } }.to_json
    stub_request(:get, api_url).to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  it 'creates an ExchangeRate from the fetched USD->MXN rate' do
    stub_api(mxn: 19.53)
    expect { described_class.new.perform }.to change(ExchangeRate, :count).by(1)
    expect(ExchangeRate.current_rate).to eq(19.53)
  end

  it 'does not create a new record when the rate is unchanged' do
    create(:exchange_rate, usd_to_mxn: 18.00)
    stub_api(mxn: 18.00)
    expect { described_class.new.perform }.not_to change(ExchangeRate, :count)
  end

  it 'does not create a record when the API call fails' do
    stub_api(mxn: 0, status: 500)
    expect { described_class.new.perform }.not_to change(ExchangeRate, :count)
  end

  it 'ignores a non-positive rate' do
    stub_api(mxn: 0)
    expect { described_class.new.perform }.not_to change(ExchangeRate, :count)
  end

  it 'honors EXCHANGE_RATE_API_URL override' do
    custom = 'https://example.test/rates'
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('EXCHANGE_RATE_API_URL', anything).and_return(custom)
    stub_request(:get, custom).to_return(
      status: 200,
      body: { 'rates' => { 'MXN' => 20.1 } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    expect { described_class.new.perform }.to change(ExchangeRate, :count).by(1)
    expect(ExchangeRate.current_rate).to eq(20.1)
  end
end
