# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::Config do
  let!(:user) { create(:user) }

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

  def pin(variable, value)
    ENV[variable] = value
    InstanceSettings::Resolver.reset!
  end

  def store(key, value)
    InstanceSetting.create!(key: key, value: value)
    InstanceSettings::Resolver.reset!
  end

  describe '.for' do
    it 'ignores the user, since one provider serves the whole instance' do
      store('photon_api_host', 'photon.shared.example.com')

      expect(described_class.for(user).host).to eq('photon.shared.example.com')
      expect(described_class.for(nil).host).to eq('photon.shared.example.com')
    end

    it 'never reads a per-user service setting' do
      create(:service_setting, :geoapify, :active, user: user)

      config = described_class.for(user)

      expect(config.source).to eq(:none)
      expect(config.enabled?).to be(false)
      expect(config.provider).to be_nil
    end

    it 'reports komoot for the komoot host' do
      pin('PHOTON_API_HOST', 'photon.komoot.io')

      expect(described_class.for(user).komoot?).to be(true)
    end

    it 'resolves a paid provider' do
      pin('GEOAPIFY_API_KEY', 'env-key')

      config = described_class.for(user)

      expect(config.provider).to eq(:geoapify)
      expect(config.api_key).to eq('env-key')
      expect(config.paid_provider?).to be(true)
    end
  end

  describe '#cache_digest' do
    it 'differs between providers and stays stable for the same config' do
      photon = described_class.new(source: :stored, provider: :photon, host: 'photon.example.com')
      geoapify = described_class.new(source: :stored, provider: :geoapify, api_key: 'key')

      expect(photon.cache_digest).not_to eq(geoapify.cache_digest)
      expect(photon.cache_digest).to eq(photon.cache_digest)
    end

    it 'changes when the api key rotates' do
      base = described_class.new(source: :stored, provider: :photon, host: 'photon.example.com', api_key: 'old')
      rotated = described_class.new(source: :stored, provider: :photon, host: 'photon.example.com', api_key: 'new')

      expect(base.cache_digest).not_to eq(rotated.cache_digest)
    end

    it 'does not contain the raw api key' do
      store('geoapify_api_key', 'test-api-key')

      expect(described_class.for(user).cache_digest).not_to include('test-api-key')
    end

    it 'uses the full digest so configs cannot be aliased by crafted collisions' do
      store('photon_api_host', 'photon.example.com')

      expect(described_class.for(user).cache_digest.length).to eq(64)
    end
  end

  describe '#provider_display_name' do
    it 'names the resolved provider' do
      store('geoapify_api_key', 'key')

      expect(described_class.for(user).provider_display_name).to eq('Geoapify')
    end
  end

  describe '#rps' do
    it 'reads a stored rate' do
      store('photon_api_host', 'photon.mine.example.com')
      store('reverse_geocoding_rps', 4)

      expect(described_class.for(user).rps).to eq(4.0)
    end

    it 'is nil when no rate is set' do
      store('photon_api_host', 'photon.mine.example.com')

      expect(described_class.for(user).rps).to be_nil
    end

    it 'is nil when geocoding is disabled' do
      expect(described_class.for(user).rps).to be_nil
    end

    it 'reads a rate the environment pins' do
      pin('PHOTON_API_HOST', 'photon.env.example.com')
      pin('REVERSE_GEOCODING_RPS', '5')

      expect(described_class.for(user).rps).to eq(5.0)
    end

    it 'pins a komoot host to one request per second whatever the rate says' do
      pin('PHOTON_API_HOST', 'photon.komoot.io')
      pin('REVERSE_GEOCODING_RPS', '40')

      expect(described_class.for(user).rps).to eq(1.0)
    end

    it 'defaults a chibigeo host to the free tier' do
      pin('PHOTON_API_HOST', 'app.chibigeo.com/v1/photon')

      expect(described_class.for(user).rps).to eq(1.0)
    end

    it 'clamps a rate that exceeds the chibigeo ceiling' do
      pin('PHOTON_API_HOST', 'app.chibigeo.com/v1/photon')
      pin('REVERSE_GEOCODING_RPS', '100')

      expect(described_class.for(user).rps).to eq(25.0)
    end
  end

  describe '.default_fallback' do
    it 'paces the gem default at the public Nominatim policy' do
      config = described_class.default_fallback

      expect(config.provider).to eq(Geocoder.config.lookup)
      expect(config.rps).to eq(1.0)
    end
  end
end
