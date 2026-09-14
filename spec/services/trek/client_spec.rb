# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trek::Client do
  let(:source) do
    instance_double(
      TripSource,
      base_url: 'https://trek.example.test',
      api_key: 'trek_test_key',
      resolved_base_url_ip!: '93.184.216.34'
    )
  end

  subject(:client) { described_class.new(source) }

  it 'lists trips with a Bearer token' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .with(headers: { 'Authorization' => 'Bearer trek_test_key', 'Accept' => 'application/json' })
      .to_return(status: 200, body: { trips: [{ id: 12, title: 'Tuscany' }] }.to_json)

    expect(client.trips).to eq([{ 'id' => 12, 'title' => 'Tuscany' }])
    expect(source).to have_received(:resolved_base_url_ip!)
  end

  it 'turns a non-success response into an error that retains the status' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 401, body: { error: 'unknown key' }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error) { |error| expect(error.status).to eq(401) }
  end

  it 'rejects a trip list with an entry that cannot be identified' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{}] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end

  it 'rejects a JSON response whose root is not an object' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips').to_return(status: 200, body: [].to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /trip list/)
  end

  it 'rejects a trip list with a non-scalar identifier' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{ id: [] }] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end

  it 'rejects duplicate identifiers after normalization' do
    stub_request(:get, 'https://trek.example.test/api/v1/trips')
      .to_return(status: 200, body: { trips: [{ id: 12 }, { id: '12' }] }.to_json)

    expect { client.trips }.to raise_error(Trek::Client::Error, /invalid trip/)
  end
end
