# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place search against a provider that rejects the request' do
  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  around do |example|
    original = Geocoder.config.to_hash.dup
    Geocoder.configure(
      lookup: :photon,
      photon: { host: 'photon.test' },
      use_https: false,
      cache: nil
    )
    example.run
  ensure
    Geocoder::Configuration.instance.data = original
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_call_original
    allow(ExceptionReporter).to receive(:call)
    allow(Rails.logger).to receive(:warn)

    stub_request(:get, %r{\Ahttp://photon\.test/}).to_return(status: 400, body: '', headers: {})
  end

  it 'returns [] from a forward search without reporting an application exception' do
    result = Places::Search.new(query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call

    expect(result).to eq([])
    expect(ExceptionReporter).not_to have_received(:call)
    expect(Rails.logger).to have_received(:warn).with(/Place search provider error: Geocoder::InvalidRequest/)
  end

  it 'returns [] from a nearby search without reporting an application exception' do
    result = Places::NearbySearch.new(latitude: lat, longitude: lon).call

    expect(result).to eq([])
    expect(ExceptionReporter).not_to have_received(:call)
    expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error: Geocoder::InvalidRequest/)
  end

  it 'handles a provider container that refuses the connection' do
    stub_request(:get, %r{\Ahttp://photon\.test/}).to_raise(Errno::ECONNREFUSED)

    expect(Places::Search.new(query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    expect(ExceptionReporter).not_to have_received(:call)
    expect(Rails.logger).to have_received(:warn).with(/Place search provider error: Errno::ECONNREFUSED/)
  end

  it 'handles a provider hostname that does not resolve' do
    stub_request(:get, %r{\Ahttp://photon\.test/}).to_raise(SocketError)

    expect(Places::NearbySearch.new(latitude: lat, longitude: lon).call).to eq([])
    expect(ExceptionReporter).not_to have_received(:call)
    expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error: SocketError/)
  end

  it 'still reports when the provider rejects the credentials' do
    stub_request(:get, %r{\Ahttp://photon\.test/}).to_return(status: 401, body: '', headers: {})

    expect(Places::Search.new(query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    expect(ExceptionReporter).to have_received(:call).with(instance_of(Geocoder::RequestDenied), anything)
  end
end
