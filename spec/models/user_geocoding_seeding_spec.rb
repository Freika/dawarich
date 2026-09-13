# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'geocoding seeding' do
  before do
    allow(DawarichSettings).to receive_messages(
      self_hosted?: true,
      reverse_geocoding_enabled?: true,
      photon_enabled?: true,
      geoapify_enabled?: false,
      nominatim_enabled?: false,
      locationiq_enabled?: false,
      photon_use_https?: true
    )
    stub_const('PHOTON_API_HOST', 'photon.env.example.com')
    stub_const('PHOTON_API_KEY', 'env-photon-key')
  end

  context 'when the resolver flag is off' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(false) }

    it 'seeds the new user from the environment, as before instance settings existed' do
      user = create(:user)

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon', active: true)).to be_present
    end

    it 'does not seed on cloud instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

      user = create(:user, skip_auto_trial: true)

      expect(user.service_settings.service_geocoding).to be_empty
    end

    it 'does not abort user creation when seeding raises' do
      allow(Geocoding::SeedFromEnv).to receive(:call).and_raise(StandardError, 'boom')
      allow(ExceptionReporter).to receive(:call)

      expect { create(:user) }.not_to raise_error
      expect(ExceptionReporter).to have_received(:call)
    end
  end

  context 'when the resolver flag is on' do
    before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

    it 'does not create per-user geocoding settings' do
      user = create(:user)

      expect(user.service_settings.service_geocoding).to be_empty
    end
  end
end
