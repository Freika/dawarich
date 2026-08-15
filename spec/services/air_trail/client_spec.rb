# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::Client do
  let(:client) { described_class.new('https://airtrail.example', 'secret-key') }

  describe '#flights' do
    it 'GETs the flight list with a bearer token and returns the flights array' do
      stub = stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
             .with(headers: { 'Authorization' => 'Bearer secret-key' })
             .to_return(status: 200, body: { success: true, flights: [{ 'id' => 1 }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(client.flights).to eq([{ 'id' => 1 }])
      expect(stub).to have_been_requested
    end

    it 'strips a trailing slash from the url' do
      stub = stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
             .to_return(status: 200, body: { success: true, flights: [] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      described_class.new('https://airtrail.example/', 'k').flights
      expect(stub).to have_been_requested
    end

    it 'raises AirTrail::Client::Error on non-2xx' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_return(status: 401, body: 'nope')

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end

    it 'raises AirTrail::Client::Error when success is false' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_return(status: 200, body: { success: false }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end
  end
end
