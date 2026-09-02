# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::SeedFromEnv do
  let(:user) { create(:user) }

  def stub_photon_env(host: 'photon.env.example.com', key: 'env-photon-key', https: true)
    allow(DawarichSettings).to receive_messages(
      reverse_geocoding_enabled?: true,
      photon_enabled?: true,
      photon_use_https?: https
    )
    stub_const('PHOTON_API_HOST', host)
    stub_const('PHOTON_API_KEY', key)
  end

  def stub_geoapify_env
    allow(DawarichSettings).to receive_messages(
      reverse_geocoding_enabled?: true,
      geoapify_enabled?: true
    )
    stub_const('GEOAPIFY_API_KEY', 'env-geo-key')
  end

  before do
    allow(DawarichSettings).to receive_messages(
      self_hosted?: true,
      reverse_geocoding_enabled?: false,
      photon_enabled?: false,
      geoapify_enabled?: false,
      nominatim_enabled?: false,
      locationiq_enabled?: false
    )
  end

  describe '.call' do
    it 'creates an active photon row from ENV' do
      stub_photon_env

      described_class.call(user)

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row).to be_present
      expect(row.active).to be(true)
      expect(row.host).to eq('photon.env.example.com')
      expect(row.use_https).to be(true)
      expect(row.api_key).to eq('env-photon-key')
    end

    it 'is idempotent' do
      stub_photon_env

      described_class.call(user)

      expect { described_class.call(user) }.not_to change(ServiceSetting, :count)
    end

    it 'creates rows for every configured ENV provider and activates the chain winner' do
      stub_photon_env
      allow(DawarichSettings).to receive(:geoapify_enabled?).and_return(true)
      stub_const('GEOAPIFY_API_KEY', 'env-geo-key')

      described_class.call(user)

      expect(user.service_settings.service_geocoding.pluck(:provider)).to match_array(%w[photon geoapify])
      expect(user.service_settings.service_geocoding.find_by(active: true).provider).to eq('photon')
    end

    it 'does nothing on non-self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      stub_photon_env

      expect { described_class.call(user) }.not_to change(ServiceSetting, :count)
    end

    it 'does nothing without provider ENV' do
      expect { described_class.call(user) }.not_to change(ServiceSetting, :count)
    end

    it 'never steals active from a pre-existing user-configured row' do
      create(:service_setting, :geoapify, :active, user: user)
      stub_photon_env

      described_class.call(user)

      expect(user.service_settings.service_geocoding.find_by(active: true).provider).to eq('geoapify')
      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').active).to be(false)
    end

    it 'forces https for https-only photon hosts' do
      stub_photon_env(host: 'photon.komoot.io', https: false)

      described_class.call(user)

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').use_https).to be(true)
    end

    it 'skips an unseedable provider and continues with the others' do
      stub_photon_env(host: 'invalid host with spaces')
      allow(DawarichSettings).to receive(:geoapify_enabled?).and_return(true)
      stub_const('GEOAPIFY_API_KEY', 'env-geo-key')
      allow(ExceptionReporter).to receive(:call)

      expect { described_class.call(user) }.not_to raise_error

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon')).to be_nil
      geoapify = user.service_settings.service_geocoding.find_by(provider: 'geoapify')
      expect(geoapify).to be_present
      expect(geoapify.active).to be(true)
      expect(ExceptionReporter).to have_received(:call).at_least(:once)
    end
  end

  # The after_create hook that used to call this service is gone: geocoding is an
  # Instance setting, so seeding a per-user copy on every signup produced rows
  # nothing reads. The service itself stays callable and is covered above.
  # spec/models/user_geocoding_seeding_spec.rb asserts the hook is not registered.
end
