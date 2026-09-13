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

  before do
    allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
  end

  def stub_no_env
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
  end

  def unstub_global_geocoder_stub
    allow(Geocoder).to receive(:search).and_call_original
  end

  describe 'ENV mode' do
    it 'delegates verbatim to Geocoder.search and produces the identical request' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      unstub_global_geocoder_stub
      urls = []
      stub_request(:get, /nominatim\.openstreetmap\.org/)
        .with { |req| urls << req.uri.to_s }
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712], limit: 1)
      Geocoder.search([51.3402, 12.3712], limit: 1)

      expect(urls.size).to eq(2)
      expect(urls.first).to eq(urls.last)
    end
  end

  describe 'disabled mode' do
    before { stub_no_env }

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

  describe 'user mode' do
    before { stub_no_env }

    it 'sends photon requests to the user host with the X-Api-Key header over https' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.mine.example.com', 'use_https' => true },
                                        api_key: 'photon-key')
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
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.mine.example.com', 'rps' => 1 })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
      described_class.call(user: user, query: [51.3402, 12.3712], limit: 1)

      results = described_class.call(user: user, query: [51.3402, 12.3712], limit: 1, max_wait: 0.2)

      expect(results).to be_nil
      expect(WebMock).to have_requested(:get, %r{https://photon\.mine\.example\.com/reverse}).once
    end

    it 'passes the wait budget through with_config' do
      Geocoding::RateLimiter.reset!
      config = Geocoding::Config.new(source: :user, provider: :photon, host: 'photon.mine.example.com', rps: 1)
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
      described_class.with_config(config: config, query: [51.3402, 12.3712], limit: 1)

      result = described_class.with_config(config: config, query: [51.3402, 12.3712], limit: 1, max_wait: 0.2)

      expect(result).to be_nil
    end

    it 'respects use_https false for photon' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.mine.example.com', 'use_https' => false })
      stub_request(:get, %r{http://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, %r{http://photon\.mine\.example\.com/reverse})
    end

    it 'sends the geoapify api key as a query param' do
      create(:service_setting, :geoapify, :active, user: user, api_key: 'geo-key')
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
      create(:service_setting, :locationiq, :active, user: user, api_key: 'liq-key')
      stub_request(:get, %r{https://us1\.locationiq\.com/v1/reverse})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to(
        have_requested(:get, %r{https://us1\.locationiq\.com/v1/reverse})
          .with(query: hash_including('key' => 'liq-key'))
      )
    end

    it 'sends nominatim requests to the user host with the configured scheme' do
      create(:service_setting, :nominatim, :active, user: user,
                                                    config: { 'host' => 'nominatim.mine.example.com',
                                                              'use_https' => false })
      stub_request(:get, %r{http://nominatim\.mine\.example\.com/reverse})
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, %r{http://nominatim\.mine\.example\.com/reverse})
    end

    it 'passes per-query options through (limit, distance_sort)' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712], limit: 7, distance_sort: true)

      expect(WebMock).to(
        have_requested(:get, %r{https://photon\.mine\.example\.com/reverse})
          .with(query: hash_including('limit' => '7', 'distance_sort' => 'true'))
      )
    end

    it 'leaves the global Geocoder config deep-unchanged' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' },
                                        api_key: 'photon-key')
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
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      expect(described_class.call(user: user, query: '')).to eq([])
      expect(described_class.call(user: user, query: [nil, nil])).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end

    it 'returns [] without HTTP when required fields are missing' do
      row = create(:service_setting, :geoapify, :active, user: user)
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = NULL WHERE id = #{row.id}"
      )

      expect(described_class.call(user: user, query: [51.3402, 12.3712])).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end

    it 'raises the same provider errors as ENV mode (always_raise inherited)' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse}).to_timeout

      expect do
        described_class.call(user: user, query: [51.3402, 12.3712])
      end.to raise_error(Geocoder::LookupTimeout)
    end

    it 'runs two users with different providers back-to-back against their own hosts' do
      other = create(:user)
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.a.example.com' })
      create(:service_setting, :active, user: other, config: { 'host' => 'photon.b.example.com' })
      stub_request(:get, %r{https://photon\.a\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://photon\.b\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      described_class.call(user: user, query: [51.3402, 12.3712])
      described_class.call(user: other, query: [51.3402, 12.3712])

      expect(WebMock).to have_requested(:get, /photon\.a\.example\.com/).once
      expect(WebMock).to have_requested(:get, /photon\.b\.example\.com/).once
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
      stub_no_env
      Geocoding::RateLimiter.reset!
      allow(Geocoding::RateLimiter).to receive(:sleep)
    end

    def stub_photon(host)
      stub_request(:get, /#{Regexp.escape(host)}/)
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'paces successive user-mode lookups' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.rated.example.com', 'rps' => 5 })
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(0.2)).once
    end

    it 'paces komoot to one request a second however many workers are running' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.komoot.io' })
      stub_photon('photon.komoot.io')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(1.0)).once
    end

    it 'does not pace a user who set no rate' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.rated.example.com' })
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'burns no slot on a lookup skipped for a blank query' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.rated.example.com', 'rps' => 5 })
      stub_photon('photon.rated.example.com')

      2.times { described_class.call(user: user, query: '') }
      described_class.call(user: user, query: [51.3402, 12.3712])

      expect(Geocoding::RateLimiter).not_to have_received(:sleep)
    end

    it 'burns no slot when the provider config is incomplete' do
      setting = create(:service_setting, :active, user: user,
                                                  config: { 'host' => 'photon.rated.example.com', 'rps' => 5 })
      setting.update_column(:config, setting.config.merge('host' => ''))

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

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

    it 'paces an ENV-managed instance too' do
      allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: true, photon_enabled?: true,
                                                  photon_use_https?: true)
      stub_const('PHOTON_API_HOST', 'photon.env.example.com')
      stub_const('PHOTON_API_KEY', nil)
      stub_const('REVERSE_GEOCODING_RPS', '5')
      unstub_global_geocoder_stub
      stub_request(:get, /nominatim\.openstreetmap\.org/)
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      2.times { described_class.call(user: user, query: [51.3402, 12.3712]) }

      expect(Geocoding::RateLimiter).to have_received(:sleep).with(be_within(0.05).of(0.2)).once
    end
  end
end
