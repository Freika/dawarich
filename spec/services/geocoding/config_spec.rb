# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::Config do
  let!(:user) { create(:user) }

  def stub_no_env
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
  end

  def stub_photon_env(host: 'photon.env.example.com', key: nil, https: true)
    allow(DawarichSettings).to receive_messages(
      reverse_geocoding_enabled?: true,
      photon_enabled?: true,
      photon_use_https?: https
    )
    stub_const('PHOTON_API_HOST', host)
    stub_const('PHOTON_API_KEY', key)
  end

  describe 'ENV precedence' do
    it 'returns the ENV config even when the user has an active row' do
      stub_photon_env
      create(:service_setting, :geoapify, :active, user: user)

      config = described_class.for(user)

      expect(config.source).to eq(:env)
      expect(config.provider).to eq(:photon)
      expect(config.host).to eq('photon.env.example.com')
      expect(config.enabled?).to be(true)
    end

    it 'reports komoot for the komoot ENV host' do
      stub_photon_env(host: 'photon.komoot.io')

      expect(described_class.for(user).komoot?).to be(true)
    end

    it 'resolves paid ENV providers' do
      allow(DawarichSettings).to receive_messages(
        reverse_geocoding_enabled?: true,
        photon_enabled?: false,
        geoapify_enabled?: true
      )
      stub_const('PHOTON_API_HOST', nil)
      stub_const('GEOAPIFY_API_KEY', 'env-key')

      config = described_class.for(user)

      expect(config.provider).to eq(:geoapify)
      expect(config.api_key).to eq('env-key')
      expect(config.paid_provider?).to be(true)
    end

    it 'stays legal in the degenerate stubbed state with no provider constants' do
      allow(DawarichSettings).to receive_messages(
        reverse_geocoding_enabled?: true,
        photon_enabled?: false,
        geoapify_enabled?: false,
        nominatim_enabled?: false,
        locationiq_enabled?: false
      )

      config = described_class.for(user)

      expect(config.source).to eq(:env)
      expect(config.enabled?).to be(true)
      expect(config.provider).to be_nil
      expect(config.komoot?).to be(false)
      expect(config.paid_provider?).to be(false)
    end
  end

  describe 'user mode' do
    before { stub_no_env }

    it 'resolves the active photon row' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.mine.example.com', 'use_https' => false })

      config = described_class.for(user)

      expect(config.source).to eq(:user)
      expect(config.enabled?).to be(true)
      expect(config.provider).to eq(:photon)
      expect(config.host).to eq('photon.mine.example.com')
      expect(config.use_https).to be(false)
      expect(config.komoot?).to be(false)
    end

    it 'reports komoot for a user komoot row' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.komoot.io' })

      expect(described_class.for(user).komoot?).to be(true)
    end

    it 'reports paid for user geoapify and locationiq rows' do
      create(:service_setting, :geoapify, :active, user: user)

      config = described_class.for(user)

      expect(config.paid_provider?).to be(true)
      expect(config.api_key).to eq('test-api-key')
    end

    it 'is disabled when the user has only inactive rows' do
      create(:service_setting, user: user)

      config = described_class.for(user)

      expect(config.source).to eq(:none)
      expect(config.enabled?).to be(false)
    end

    it 'is disabled when the user has no rows' do
      config = described_class.for(user)

      expect(config.source).to eq(:none)
      expect(config.enabled?).to be(false)
      expect(config.provider).to be_nil
    end

    it 'is disabled when the active row credentials are unreadable' do
      row = create(:service_setting, :geoapify, :active, user: user)
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = 'garbage' WHERE id = #{row.id}"
      )

      expect(described_class.for(user).enabled?).to be(false)
    end

    it 'logs a warning when the active row credentials are unreadable' do
      row = create(:service_setting, :geoapify, :active, user: user)
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = 'garbage' WHERE id = #{row.id}"
      )

      allow(Rails.logger).to receive(:warn)

      described_class.for(user)

      expect(Rails.logger).to have_received(:warn).with(/cannot be decrypted/)
    end

    it 'accepts a bare user_id without loading the user' do
      create(:service_setting, :active, user: user)

      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        queries << payload[:sql] unless payload[:name] == 'SCHEMA'
      end

      config = nil
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        config = described_class.for(user.id)
      end

      expect(config.enabled?).to be(true)
      expect(queries.grep(/FROM "users"/)).to be_empty
    end

    it 'is disabled for a nil user' do
      expect(described_class.for(nil).enabled?).to be(false)
    end
  end

  describe 'nil user with ENV' do
    it 'falls back to the ENV config' do
      stub_photon_env

      config = described_class.for(nil)

      expect(config.source).to eq(:env)
      expect(config.enabled?).to be(true)
    end
  end

  describe '.for_user_settings' do
    it 'skips the ENV branch even when ENV is set' do
      stub_photon_env
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      config = described_class.for_user_settings(user)

      expect(config.source).to eq(:user)
      expect(config.host).to eq('photon.mine.example.com')
    end

    it 'is disabled when the user has no active row' do
      stub_photon_env

      expect(described_class.for_user_settings(user).enabled?).to be(false)
    end
  end

  describe '#cache_digest' do
    before { stub_no_env }

    it 'differs between users with different providers and stays stable for the same config' do
      other = create(:user)
      create(:service_setting, :active, user: user)
      create(:service_setting, :geoapify, :active, user: other)

      expect(described_class.for(user).cache_digest).not_to eq(described_class.for(other).cache_digest)
      expect(described_class.for(user).cache_digest).to eq(described_class.for(user).cache_digest)
    end

    it 'does not contain the raw api key' do
      create(:service_setting, :geoapify, :active, user: user)

      expect(described_class.for(user).cache_digest).not_to include('test-api-key')
    end

    it 'uses the full digest so configs cannot be aliased by crafted collisions' do
      create(:service_setting, :active, user: user)

      expect(described_class.for(user).cache_digest.length).to eq(64)
    end
  end

  describe '#provider_display_name' do
    it 'matches the current Geocoder.config-based name in ENV mode' do
      stub_photon_env

      expect(described_class.for(user).provider_display_name).to eq('Photon')
    end

    it 'names the user provider in user mode' do
      stub_no_env
      create(:service_setting, :geoapify, :active, user: user)

      expect(described_class.for(user).provider_display_name).to eq('Geoapify')
    end
  end
  describe '#rps' do
    it 'reads the rate from the active user row' do
      stub_no_env
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com', 'rps' => 4 })

      expect(described_class.for(user).rps).to eq(4.0)
    end

    it 'is nil when the user left the rate unset' do
      stub_no_env
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      expect(described_class.for(user).rps).to be_nil
    end

    it 'pins a komoot user row to one request per second' do
      stub_no_env
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.komoot.io', 'rps' => 40 })

      expect(described_class.for(user).rps).to eq(1.0)
    end

    it 'is nil when geocoding is disabled' do
      stub_no_env

      expect(described_class.for(user).rps).to be_nil
    end

    it 'reads the ENV rate for an ENV-managed instance' do
      stub_photon_env
      stub_const('REVERSE_GEOCODING_RPS', '5')

      expect(described_class.for(user).rps).to eq(5.0)
    end

    it 'is nil for an ENV-managed instance that set no rate' do
      stub_photon_env
      stub_const('REVERSE_GEOCODING_RPS', nil)

      expect(described_class.for(user).rps).to be_nil
    end

    it 'pins an ENV komoot host to one request per second whatever the ENV rate says' do
      stub_photon_env(host: 'photon.komoot.io')
      stub_const('REVERSE_GEOCODING_RPS', '40')

      expect(described_class.for(user).rps).to eq(1.0)
    end

    it 'defaults an ENV chibigeo host to the free tier' do
      stub_photon_env(host: 'app.chibigeo.com/v1/photon')
      stub_const('REVERSE_GEOCODING_RPS', nil)

      expect(described_class.for(user).rps).to eq(1.0)
    end

    it 'clamps an ENV rate that exceeds the chibigeo ceiling' do
      stub_photon_env(host: 'app.chibigeo.com/v1/photon')
      stub_const('REVERSE_GEOCODING_RPS', '100')

      expect(described_class.for(user).rps).to eq(25.0)
    end
  end
end
