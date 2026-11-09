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

  it 'retries a timeout' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_timeout
      .then
      .to_return(status: 200, body: { data: { cars: [] } }.to_json)

    expect(described_class.new(base_url).cars).to eq([])
    expect(a_request(:get, "#{base_url}/api/v1/cars")).to have_been_made.twice
  end

  it 'honors a one-attempt request budget' do
    request = stub_request(:get, "#{base_url}/api/v1/cars").to_raise(Errno::ECONNRESET)

    expect { described_class.new(base_url, max_attempts: 1).cars }
      .to raise_error(TeslaMate::Client::Error)
    expect(request).to have_been_requested.once
  end

  it 'uses Basic authentication in preference to a bearer token' do
    request = stub_request(:get, "#{base_url}/api/v1/cars")
              .with(basic_auth: %w[proxy secret])
              .to_return(status: 200, body: { data: { cars: nil } }.to_json)

    expect(described_class.new(base_url, username: 'proxy', password: 'secret', api_token: 'token').cars).to eq([])
    expect(request).to have_been_requested
  end

  it 'retries a server error up to the attempt budget' do
    request = stub_request(:get, "#{base_url}/api/v1/cars").to_return(status: 503)

    expect { described_class.new(base_url).cars }.to raise_error(TeslaMate::Client::Error, /503/)
    expect(request).to have_been_requested.times(3)
  end

  it 'refuses a URL that resolves to a blocked address without sending or retrying' do
    stub_host_addresses('teslamate.example', '169.254.169.254')
    request = stub_request(:get, "#{base_url}/api/v1/cars")

    expect { described_class.new(base_url).cars }.to raise_error(TeslaMate::Client::Error)
    expect(request).not_to have_been_requested
  end

  it 'does not follow a redirect' do
    stub_request(:get, "#{base_url}/api/v1/cars")
      .to_return(status: 302, headers: { 'Location' => 'https://elsewhere.example/api/v1/cars' })
    followed = stub_request(:get, 'https://elsewhere.example/api/v1/cars')

    expect { described_class.new(base_url).cars }.to raise_error(TeslaMate::Client::Error, /redirect/)
    expect(followed).not_to have_been_requested
  end

  it 'sends the drive window as query parameters, keeping the UTC offset' do
    end_date = Time.new(2026, 11, 9, 10, 0, 0, '+01:00')
    request = stub_request(:get, "#{base_url}/api/v1/cars/1/drives")
              .with(query: { 'page' => '1', 'show' => '100', 'endDate' => '2026-11-09T10:00:00+01:00' })
              .to_return(status: 200, body: { data: { drives: [] } }.to_json)

    described_class.new(base_url).drives(1, page: 1, show: 100, end_date: end_date)

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

  it 'rejects non-positive pagination values before making a request' do
    expect do
      described_class.new(base_url).drives(1, page: 0, show: 100, end_date: Time.current)
    end.to raise_error(TeslaMate::Client::Error, /page must be a positive integer/)

    expect(a_request(:get, %r{#{base_url}/api/v1/cars/1/drives})).not_to have_been_made
  end

  it 'rejects non-integral pagination values before making a request' do
    expect do
      described_class.new(base_url).drives(1, page: 1.5, show: 100, end_date: Time.current)
    end.to raise_error(TeslaMate::Client::Error, /page must be a positive integer/)

    expect(a_request(:get, %r{#{base_url}/api/v1/cars/1/drives})).not_to have_been_made
  end
end
