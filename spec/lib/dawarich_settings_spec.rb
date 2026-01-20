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
    context 'when PHOTON_API_HOST is present' do
      before { stub_const('PHOTON_API_HOST', 'photon.example.com') }

      it 'returns true' do
        expect(described_class.photon_enabled?).to be true
      end
    end

    context 'when PHOTON_API_HOST is blank' do
      before { stub_const('PHOTON_API_HOST', '') }

      it 'returns false' do
        expect(described_class.photon_enabled?).to be false
      end
    end
  end

  describe '.photon_uses_komoot_io?' do
    context 'when PHOTON_API_HOST is komoot.io' do
      before { stub_const('PHOTON_API_HOST', 'photon.komoot.io') }

      it 'returns true' do
        expect(described_class.photon_uses_komoot_io?).to be true
      end
    end

    context 'when PHOTON_API_HOST is different' do
      before { stub_const('PHOTON_API_HOST', 'photon.example.com') }

      it 'returns false' do
        expect(described_class.photon_uses_komoot_io?).to be false
      end
    end
  end

  describe '.geoapify_enabled?' do
    context 'when GEOAPIFY_API_KEY is present' do
      before { stub_const('GEOAPIFY_API_KEY', 'some-api-key') }

      it 'returns true' do
        expect(described_class.geoapify_enabled?).to be true
      end
    end

    context 'when GEOAPIFY_API_KEY is blank' do
      before { stub_const('GEOAPIFY_API_KEY', '') }

      it 'returns false' do
        expect(described_class.geoapify_enabled?).to be false
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
