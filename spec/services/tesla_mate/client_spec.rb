# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeslaMate::Client do
  let(:base_url) { 'https://teslamate.example' }

  it 'retries a transient read failure and returns cars' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_raise(Errno::ECONNRESET)
      .then
      .to_return(status: 200, body: { data: { cars: [{ car_id: 1 }] } }.to_json)

    expect(described_class.new(base_url).cars).to eq([{ 'car_id' => 1 }])
    expect(a_request(:get, "#{base_url}/api/v1/cars")).to have_been_made.twice
  end

  it 'uses Basic authentication in preference to a bearer token' do
    request = stub_request(:get, "#{base_url}/api/v1/cars")
              .with(basic_auth: %w[proxy secret])
              .to_return(status: 200, body: { data: { cars: nil } }.to_json)

    expect(described_class.new(base_url, username: 'proxy', password: 'secret', api_token: 'token').cars).to eq([])
    expect(request).to have_been_requested
  end

  it 'rejects TeslaMateApi errors returned with HTTP 200' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { error: 'Unable to load cars.' }.to_json)

    expect { described_class.new(base_url).cars }
      .to raise_error(TeslaMate::Client::Error, 'Unable to load cars.')
  end

  it 'rejects a success-shaped response without the expected cars key' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: { data: {} }.to_json)

    expect { described_class.new(base_url).cars }
      .to raise_error(TeslaMate::Client::Error, /cars data/)
  end

  it 'wraps a non-object JSON response as a client error' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 200, body: [].to_json)

    expect { described_class.new(base_url).cars }
      .to raise_error(TeslaMate::Client::Error, /invalid response/)
  end
end
