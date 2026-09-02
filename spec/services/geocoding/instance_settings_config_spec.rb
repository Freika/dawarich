# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::Config, 'resolved from instance settings' do
  let(:user) { create(:user) }

  def clear_geocoding_env
    %w[PHOTON_API_HOST PHOTON_API_KEY GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY].each do |name|
      @saved ||= {}
      @saved[name] = ENV.fetch(name, nil)
      ENV[name] = nil
    end
  end

  around do |example|
    clear_geocoding_env
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    @saved&.each { |name, value| ENV[name] = value }
    InstanceSettings::Resolver.reset!
  end

  context 'when the resolver flag is on' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

    it 'reports :env and pins when the environment supplies the provider' do
      ENV['PHOTON_API_HOST'] = 'env.example.com'
      InstanceSettings::Resolver.reset!

      config = described_class.for(user)

      expect(config.provider).to eq(:photon)
      expect(config.host).to eq('env.example.com')
      expect(config.source).to eq(:env)
      expect(config).to be_pinned
    end

    it 'reports :stored when only the database supplies the provider' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      config = described_class.for(user)

      expect(config.provider).to eq(:photon)
      expect(config.host).to eq('stored.example.com')
      expect(config.source).to eq(:stored)
      expect(config).not_to be_pinned
    end

    it 'is disabled when neither source supplies a provider' do
      config = described_class.for(user)

      expect(config).not_to be_enabled
      expect(config.source).to eq(:none)
    end

    it 'follows the provider chain when several are configured' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'geo-key')
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      expect(described_class.for(user).provider).to eq(:photon)
    end

    it 'carries a stored api key through' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'geo-key')
      InstanceSettings::Resolver.reset!

      config = described_class.for(user)

      expect(config.provider).to eq(:geoapify)
      expect(config.api_key).to eq('geo-key')
    end

    it 'never consults per-user service settings' do
      user # create before asserting: the after_create seeding hook touches ServiceSetting itself
      expect(ServiceSetting).not_to receive(:service_geocoding)

      described_class.for(user)
    end
  end

  context 'when the resolver flag is off' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(false) }

    # PHOTON_API_HOST is a boot-frozen constant, so the historical path keeps
    # reading whatever the process started with no matter what is stored.
    it 'ignores stored instance settings entirely' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      config = described_class.for(user)

      expect(config.host).not_to eq('stored.example.com')
      expect(config.source).not_to eq(:stored)
    end

    # Deliberately does not assert a particular host: PHOTON_API_HOST is a
    # boot-frozen constant, so the value differs between a developer's .env and
    # CI. What matters is that the historical path is the one being used.
    it 'resolves through the historical constant-driven path' do
      config = described_class.for(user)

      expect(config.source).to be_in(%i[env user none])
      expect(config.source).not_to eq(:stored)
    end
  end

  describe '#env_managed?' do
    it 'remains an alias for pinned so the existing view keeps working' do
      allow(InstanceSettings).to receive(:enabled?).and_return(true)
      ENV['PHOTON_API_HOST'] = 'env.example.com'
      InstanceSettings::Resolver.reset!

      expect(described_class.for(user).env_managed?).to be(true)
    end
  end
end
