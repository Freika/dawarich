# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings, 'resolved from instance settings' do
  around do |example|
    saved = ENV.fetch('PHOTON_API_HOST', nil)
    ENV['PHOTON_API_HOST'] = nil
    InstanceSettings::Resolver.reset!
    described_class.reset_memoization!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = saved
    InstanceSettings::Resolver.reset!
    described_class.reset_memoization!
  end

  context 'with the resolver enabled' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

    it 'reflects a stored provider without a process restart' do
      expect(described_class.photon_enabled?).to be(false)

      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      expect(described_class.photon_enabled?).to be(true)
    end

    it 'reflects a provider disappearing without a process restart' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!
      expect(described_class.reverse_geocoding_enabled?).to be(true)

      InstanceSetting.find_by(key: 'photon_api_host').destroy!
      InstanceSettings::Resolver.reset!

      expect(described_class.reverse_geocoding_enabled?).to be(false)
    end

    # rails_helper stubs store_geodata? to true for every example in the suite,
    # so this has to call through or it proves nothing about the implementation.
    it 'returns a stored false for store_geodata? rather than re-reading the default' do
      allow(described_class).to receive(:store_geodata?).and_call_original
      InstanceSetting.create!(key: 'store_geodata', value: false)
      InstanceSettings::Resolver.reset!

      expect(described_class.store_geodata?).to be(false)
    end

    it 'forces https for a host that only answers over TLS' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'photon.komoot.io')
      InstanceSettings::Resolver.reset!

      expect(described_class.photon_use_https?).to be(true)
    end
  end

  describe 'self_hosted?' do
    it 'stays memoised: SELF_HOSTED is genuinely boot-only' do
      first = described_class.self_hosted?

      expect(described_class.self_hosted?).to be(first)
      expect(described_class.instance_variable_get(:@self_hosted)).not_to be_nil
    end
  end
end
