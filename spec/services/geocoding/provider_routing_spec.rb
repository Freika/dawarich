# frozen_string_literal: true

require 'rails_helper'

# The initializer used to decide the provider globally via Geocoder.configure.
# Once the resolver owns that decision, every lookup has to carry its own
# provider config or requests silently fall back to the geocoder gem's default
# — public Nominatim — at whatever rate the operator had granted their own
# Photon. That is third-party abuse, not just a wrong result, so these specs
# assert on the URI actually requested.
RSpec.describe 'Geocoding provider routing' do
  let(:user) { create(:user) }

  around do |example|
    saved = ENV.fetch('PHOTON_API_HOST', nil)
    # Geocoder.config is a process-wide singleton; one example reconfiguring it
    # would otherwise leak into every spec file that runs afterwards.
    saved_geocoder = Geocoder.config.to_hash.dup
    ENV['PHOTON_API_HOST'] = nil
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = saved
    Geocoder::Configuration.instance.data = saved_geocoder
    InstanceSettings::Resolver.reset!
  end

  def requested_hosts
    hosts = []
    stub_request(:get, /.*/)
      .with { |req| hosts << req.uri.host }
      .to_return(status: 200, body: '{"features":[]}', headers: { 'Content-Type' => 'application/json' })
    yield
    hosts
  end

  context 'with the resolver enabled' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

    it 'sends an environment-pinned lookup to that host, not to the gem default' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      hosts = requested_hosts do
        Geocoding::Search.call(user: user, query: [51.34, 12.37], limit: 1)
      end

      expect(hosts).to include('pinned.example.com')
      expect(hosts).not_to include('nominatim.openstreetmap.org')
    end

    it 'sends a stored lookup to the stored host with no process restart' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      hosts = requested_hosts do
        Geocoding::Search.call(user: user, query: [51.34, 12.37], limit: 1)
      end

      expect(hosts).to include('stored.example.com')
      expect(hosts).not_to include('nominatim.openstreetmap.org')
    end

    it 'still reaches the public fallback when nothing is configured and it is allowed' do
      # spec/support/geocoder_stubs.rb stubs Geocoder.search suite-wide, and the
      # fallback path is the one branch that still goes through it, so it has to
      # call through here for the URI to be observable at all.
      allow(Geocoder).to receive(:search).and_call_original

      hosts = requested_hosts do
        Geocoding::Search.call(user: user, query: 'Leipzig', fallback_to_default: true)
      end

      expect(hosts).to include('nominatim.openstreetmap.org')
    end

    it 'makes no request at all when nothing is configured and fallback is not allowed' do
      hosts = requested_hosts do
        Geocoding::Search.call(user: user, query: 'Leipzig')
      end

      expect(hosts).to be_empty
    end
  end

  describe 'independence from the global Geocoder configuration' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

    # The initializer is deliberately left alone (it runs before the database is
    # guaranteed reachable). Routing must therefore ignore whatever provider the
    # global config happens to name, rather than depend on it being cleared.
    it 'routes to the resolved host even when the global config names another provider' do
      Geocoder.configure(lookup: :nominatim, nominatim: { host: 'wrong.example.com' })
      InstanceSetting.create!(key: 'photon_api_host', value: 'right.example.com')
      InstanceSettings::Resolver.reset!

      hosts = requested_hosts do
        Geocoding::Search.call(user: user, query: [51.34, 12.37], limit: 1)
      end

      expect(hosts).to include('right.example.com')
      expect(hosts).not_to include('wrong.example.com')
    end
  end
end

# T6's DoD: the settings "test connection" button must return a real result once
# the resolver owns geocoding. Every other with_config example builds source
# :user, so reverting DIRECT_SOURCES to `config.source == :user` would leave the
# suite green while the button silently returned [] forever.
RSpec.describe Geocoding::Search, '.with_config source handling' do
  let(:config) do
    Geocoding::Config.new(source: :stored, provider: :photon, host: 'stored.example.com', use_https: false)
  end

  it 'runs a lookup for a stored config' do
    stub_request(:get, /stored\.example\.com/)
      .to_return(status: 200, body: '{"features":[]}', headers: { 'Content-Type' => 'application/json' })

    described_class.with_config(config: config, query: [51.34, 12.37], limit: 1)

    expect(WebMock).to have_requested(:get, /stored\.example\.com/)
  end

  it 'returns [] without a request when no provider resolves' do
    disabled = Geocoding::Config.new(source: :none)

    expect(described_class.with_config(config: disabled, query: [51.34, 12.37])).to eq([])
  end
end
