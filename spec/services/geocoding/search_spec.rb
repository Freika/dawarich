# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::Search do
  let(:user) { create(:user) }

  let(:photon_body) do
    {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature',
          properties: { city: 'Leipzig', country: 'Germany', name: 'Testplatz' },
          geometry: { type: 'Point', coordinates: [12.3712, 51.3402] } }
      ]
    }.to_json
  end

  around do |example|
    variables = InstanceSettings::Registry::DEFINITIONS.values.map(&:env_var)
    saved = variables.index_with { |name| ENV.fetch(name, nil) }
    variables.each { |name| ENV[name] = nil }
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    saved.each { |name, value| ENV[name] = value }
    InstanceSettings::Resolver.reset!
  end

  before do
    use_real_geocoding_lookups
    allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
  end

  def store(settings)
    settings.each { |key, value| InstanceSetting.create!(key: key.to_s, value: value) }
    InstanceSettings::Resolver.reset!
  end

  def unstub_global_geocoder_stub
    allow(Geocoder).to receive(:search).and_call_original
  end

  describe 'disabled mode' do
    it 'returns [] without any HTTP request' do
      unstub_global_geocoder_stub

      result = described_class.call(user: user, query: [51.3402, 12.3712])

      expect(result).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end

    it 'falls back to the default global lookup when fallback_to_default is set' do
      unstub_global_geocoder_stub
      stub_request(:get, /nominatim\.openstreetmap\.org/)
        .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: 'Leipzig', fallback_to_default: true)

      expect(WebMock).to have_requested(:get, /nominatim\.openstreetmap\.org/)
    end
  end

  describe 'configured mode' do
    it 'sends photon requests to the configured host with the X-Api-Key header over https' do
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: true, photon_api_key: 'photon-key')
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      results = described_class.call(user: user, query: [51.3402, 12.3712], limit: 1)

      expect(results.first.city).to eq('Leipzig')
      expect(results.first.country).to eq('Germany')
      expect(WebMock).to(
        have_requested(:get, %r{https://photon\.mine\.example\.com/reverse})
          .with(headers: { 'X-Api-Key' => 'photon-key' })
      )
    end

    it 'returns an empty result when the rate limiter cannot grant a slot in time' do
      Geocoding::RateLimiter.reset!
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: true, reverse_geocoding_rps: 1)
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
      described_class.call(user: user, query: [51.3402, 12.3712], limit: 1)

      results = described_class.call(user: user, query: [51.3402, 12.3712], limit: 1, max_wait: 0.2)

      expect(results).to be_nil
      expect(WebMock).to have_requested(:get, %r{https://photon\.mine\.example\.com/reverse}).once
    end

    it 'passes the wait budget through with_config' do
      Geocoding::RateLimiter.reset!
      config = Geocoding::Config.new(source: :stored, provider: :photon, host: 'photon.mine.example.com', rps: 1)
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
      described_class.with_config(config: config, query: [51.3402, 12.3712], limit: 1)

      result = described_class.with_config(config: config, query: [51.3402, 12.3712], limit: 1, max_wait: 0.2)

      expect(result).to be_nil
    end

    it 'respects use_https false for photon' do
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: false)
      stub_request(:get, %r{http://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, %r{http://photon\.mine\.example\.com/reverse})
    end

    it 'sends the geoapify api key as a query param' do
      store(geoapify_api_key: 'geo-key')
      stub_request(:get, %r{https://api\.geoapify\.com/v1/geocode/reverse})
        .to_return(status: 200, body: { features: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to(
        have_requested(:get, %r{https://api\.geoapify\.com/v1/geocode/reverse})
          .with(query: hash_including('apiKey' => 'geo-key'))
      )
    end

    it 'sends locationiq requests to the locationiq host with the key param' do
      store(locationiq_api_key: 'liq-key')
      stub_request(:get, %r{https://us1\.locationiq\.com/v1/reverse})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to(
        have_requested(:get, %r{https://us1\.locationiq\.com/v1/reverse})
          .with(query: hash_including('key' => 'liq-key'))
      )
    end

    it 'sends nominatim requests to the configured host with the configured scheme' do
      store(nominatim_api_host: 'nominatim.mine.example.com', nominatim_api_use_https: false)
      stub_request(:get, %r{http://nominatim\.mine\.example\.com/reverse})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, %r{http://nominatim\.mine\.example\.com/reverse})
    end

    it 'passes per-query options through (limit, distance_sort)' do
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: true)
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712], limit: 7, distance_sort: true)

      expect(WebMock).to(
        have_requested(:get, %r{https://photon\.mine\.example\.com/reverse})
          .with(query: hash_including('limit' => '7', 'distance_sort' => 'true'))
      )
    end

    it 'leaves the global Geocoder config deep-unchanged' do
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: true, photon_api_key: 'photon-key')
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      before_headers = Geocoder.config.http_headers.dup
      before_dump = Marshal.dump(Geocoder.config.to_hash.except(:cache))

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(Geocoder.config.http_headers).to eq(before_headers)
      expect(Geocoder.config.http_headers).not_to have_key('X-Api-Key')
      expect(Marshal.dump(Geocoder.config.to_hash.except(:cache))).to eq(before_dump)
    end

    it 'returns [] for blank queries without any HTTP request' do
      store(photon_api_host: 'photon.mine.example.com')

      expect(described_class.call(user: user, query: '')).to eq([])
      expect(described_class.call(user: user, query: [nil, nil])).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end

    it 'returns [] without HTTP when required fields are missing' do
      config = Geocoding::Config.new(source: :stored, provider: :geoapify)

      expect(described_class.with_config(config: config, query: [51.3402, 12.3712])).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end

    it 'raises provider errors (always_raise inherited)' do
      store(photon_api_host: 'photon.mine.example.com', photon_api_use_https: true)
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse}).to_timeout

      expect do
        described_class.call(user: user, query: [51.3402, 12.3712])
      end.to raise_error(Geocoder::LookupTimeout)
    end

    it 'sends every user to the same instance host' do
      other = create(:user)
      store(photon_api_host: 'photon.shared.example.com', photon_api_use_https: true)
      stub_request(:get, %r{https://photon\.shared\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])
      described_class.call(user: other, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, /photon\.shared\.example\.com/).twice
    end
  end

  describe 'gem seam canary' do
    it 'still routes lookup configuration through Base#configuration' do
      expect(Geocoder::Lookup::Photon.instance_method(:configuration).owner)
        .to eq(Geocoder::Lookup::Base)

      merged = Geocoder.config_for_lookup(:photon).merge({})

      expect(merged).to be_a(Hash)
      expect(merged).to respond_to(:api_key)
    end
  end
  describe 'rate limiting' do
    before do
      Geocoding::RateLimiter.reset!
      allow(Geocoding::RateLimiter).to receive(:sleep)
    end

    def stub_photon(host)
      stub_request(:get, /#{Regexp.escape(host)}/)
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'paces successive lookups' do
      store(photon_api_host: 'photon.rated.example.com', reverse_geocoding_rps: 5)
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(0.2)).once
    end

    it 'paces komoot to one request a second however many workers are running' do
      store(photon_api_host: 'photon.komoot.io')
      stub_photon('photon.komoot.io')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(1.0)).once
    end

    it 'does not pace an instance that set no rate' do
      store(photon_api_host: 'photon.rated.example.com')
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'burns no slot on a lookup skipped for a blank query' do
      store(photon_api_host: 'photon.rated.example.com', reverse_geocoding_rps: 5)
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: '') }
      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'burns no slot when the provider config is incomplete' do
      config = Geocoding::Config.new(source: :stored, provider: :geoapify, rps: 5)

      2.times { described_class.with_config(config: config, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'paces the no-provider fallback to the public Nominatim policy' do
      unstub_global_geocoder_stub
      stub_request(:get, /nominatim\.openstreetmap\.org/)
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      2.times { described_class.call(user: user, query: 'Leipzig', fallback_to_default: true) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(1.0)).once
    end

    it 'still returns nothing for a disabled config without the fallback' do
      expect(described_class.call(user: user, query: 'Leipzig')).to eq([])
      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'paces a rate the environment pins' do
      ENV['PHOTON_API_HOST'] = 'photon.env.example.com'
      ENV['REVERSE_GEOCODING_RPS'] = '5'
      InstanceSettings::Resolver.reset!
      stub_photon('photon.env.example.com')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(0.2)).once
    end
  end
end
