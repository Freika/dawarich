# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  before do
    described_class.instance_variables.each do |ivar|
      described_class.remove_instance_variable(ivar)
    end
  end

  describe '.reverse_geocoding_enabled?' do
    context 'when photon is enabled' do
      before do
        allow(described_class).to receive(:photon_enabled?).and_return(true)
        allow(described_class).to receive(:geoapify_enabled?).and_return(false)
      end

      it 'returns true' do
        expect(described_class.reverse_geocoding_enabled?).to be true
      end
    end

    context 'when geoapify is enabled' do
      before do
        allow(described_class).to receive(:photon_enabled?).and_return(false)
        allow(described_class).to receive(:geoapify_enabled?).and_return(true)
      end

      it 'returns true' do
        expect(described_class.reverse_geocoding_enabled?).to be true
      end
    end

    context 'when neither service is enabled' do
      before do
        allow(described_class).to receive(:photon_enabled?).and_return(false)
        allow(described_class).to receive(:geoapify_enabled?).and_return(false)
      end

      it 'returns false' do
        expect(described_class.reverse_geocoding_enabled?).to be false
      end
    end
  end

  describe '.photon_enabled?' do
    context 'when PHOTON_API_HOST is set in the environment' do
      before do
        ENV['PHOTON_API_HOST'] = 'photon.example.com'
        InstanceSettings::Resolver.reset!
      end

      it 'returns true' do
        expect(described_class.photon_enabled?).to be true
      end
    end

    context 'when a Photon host is stored as an instance setting' do
      before { configure_instance_geocoding(photon_api_host: 'photon.example.com') }

      it 'returns true' do
        expect(described_class.photon_enabled?).to be true
      end
    end

    context 'when no Photon host is configured' do
      before { stub_const('PHOTON_API_HOST', 'photon.example.com') }

      it 'returns false regardless of the boot constant' do
        expect(described_class.photon_enabled?).to be false
      end
    end

    context 'when the instance settings cannot be read' do
      before do
        stub_const('PHOTON_API_HOST', 'photon.example.com')
        allow(InstanceSettings::Resolver).to receive(:value).and_raise(ActiveRecord::NoDatabaseError)
      end

      it 'falls back to the boot constant' do
        expect(described_class.photon_enabled?).to be true
      end
    end
  end

  describe '.geoapify_enabled?' do
    context 'when GEOAPIFY_API_KEY is set in the environment' do
      before do
        ENV['GEOAPIFY_API_KEY'] = 'some-api-key'
        InstanceSettings::Resolver.reset!
      end

      it 'returns true' do
        expect(described_class.geoapify_enabled?).to be true
      end
    end

    context 'when a Geoapify key is stored as an instance setting' do
      before { configure_instance_geocoding(geoapify_api_key: 'some-api-key') }

      it 'returns true' do
        expect(described_class.geoapify_enabled?).to be true
      end
    end

    context 'when no Geoapify key is configured' do
      before { stub_const('GEOAPIFY_API_KEY', 'some-api-key') }

      it 'returns false regardless of the boot constant' do
        expect(described_class.geoapify_enabled?).to be false
      end
    end

    context 'when the instance settings cannot be read' do
      before do
        stub_const('GEOAPIFY_API_KEY', 'some-api-key')
        allow(InstanceSettings::Resolver).to receive(:value).and_raise(ActiveRecord::NoDatabaseError)
      end

      it 'falls back to the boot constant' do
        expect(described_class.geoapify_enabled?).to be true
      end
    end
  end

  describe '.oidc_enabled?' do
    # Allow the real implementation to be called in these tests
    before do
      allow(described_class).to receive(:oidc_enabled?).and_call_original
    end

    context 'when self-hosted and OIDC providers include openid_connect' do
      before do
        stub_const('SELF_HOSTED', true)
        stub_const('OMNIAUTH_PROVIDERS', %i[openid_connect])
      end

      it 'returns true' do
        expect(described_class.oidc_enabled?).to be true
      end
    end

    context 'when self-hosted but OIDC providers do not include openid_connect' do
      before do
        stub_const('SELF_HOSTED', true)
        stub_const('OMNIAUTH_PROVIDERS', [])
      end

      it 'returns false' do
        expect(described_class.oidc_enabled?).to be false
      end
    end

    context 'when not self-hosted' do
      before do
        stub_const('SELF_HOSTED', false)
        stub_const('OMNIAUTH_PROVIDERS', %i[openid_connect])
      end

      it 'returns false' do
        expect(described_class.oidc_enabled?).to be false
      end
    end

    context 'when not self-hosted with github/google providers (cloud mode)' do
      before do
        stub_const('SELF_HOSTED', false)
        stub_const('OMNIAUTH_PROVIDERS', %i[github google_oauth2])
      end

      it 'returns false (OAuth in cloud is supplementary, not OIDC-only)' do
        expect(described_class.oidc_enabled?).to be false
      end
    end
  end
end
