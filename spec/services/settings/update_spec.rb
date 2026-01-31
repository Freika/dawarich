# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Settings::Update do
  let(:user) { create(:user) }

  describe '#call' do
    context 'when updating basic settings' do
      let(:settings_params) { { 'meters_between_routes' => '1000', 'minutes_between_routes' => '10' } }
      let(:service) { described_class.new(user, settings_params) }

      it 'updates the user settings' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:notices]).to include('Settings updated')
        expect(user.reload.settings['meters_between_routes']).to eq('1000')
        expect(user.reload.settings['minutes_between_routes']).to eq('10')
      end
    end

    context 'when user update fails' do
      let(:settings_params) { { 'meters_between_routes' => '1000' } }
      let(:service) { described_class.new(user, settings_params) }

      before do
        allow(user).to receive(:update).and_return(false)
      end

      it 'returns failure with alert' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:alerts]).to include('Settings could not be updated')
      end
    end

    context 'when refresh_photos_cache is requested' do
      let(:settings_params) { { 'meters_between_routes' => '1000' } }
      let(:service) { described_class.new(user, settings_params, refresh_photos_cache: true) }
      let(:cache_cleaner) { instance_double(Photos::CacheCleaner) }

      before do
        allow(Photos::CacheCleaner).to receive(:new).with(user).and_return(cache_cleaner)
        allow(cache_cleaner).to receive(:call)
      end

      it 'clears the photo cache' do
        service.call

        expect(cache_cleaner).to have_received(:call)
      end

      it 'includes photo cache notice' do
        result = service.call

        expect(result[:notices]).to include('Photo cache refreshed')
      end
    end

    context 'when immich settings change' do
      let(:settings_params) { { 'immich_url' => 'https://immich.test', 'immich_api_key' => 'new-key' } }
      let(:service) { described_class.new(user, settings_params) }

      context 'when connection test succeeds' do
        before do
          allow_any_instance_of(Immich::ConnectionTester).to receive(:call)
            .and_return({ success: true, message: 'Immich connection verified' })
        end

        it 'includes success message in notices' do
          result = service.call

          expect(result[:notices]).to include('Immich connection verified')
          expect(result[:alerts]).to be_empty
        end
      end

      context 'when connection test fails' do
        before do
          allow_any_instance_of(Immich::ConnectionTester).to receive(:call)
            .and_return({ success: false, error: 'Immich connection failed: 500' })
        end

        it 'includes error message in alerts' do
          result = service.call

          expect(result[:alerts]).to include('Immich connection failed: 500')
        end
      end
    end

    context 'when photoprism settings change' do
      let(:settings_params) { { 'photoprism_url' => 'https://photoprism.test', 'photoprism_api_key' => 'new-key' } }
      let(:service) { described_class.new(user, settings_params) }

      context 'when connection test succeeds' do
        before do
          allow_any_instance_of(Photoprism::ConnectionTester).to receive(:call)
            .and_return({ success: true, message: 'Photoprism connection verified' })
        end

        it 'includes success message in notices' do
          result = service.call

          expect(result[:notices]).to include('Photoprism connection verified')
          expect(result[:alerts]).to be_empty
        end
      end

      context 'when connection test fails' do
        before do
          allow_any_instance_of(Photoprism::ConnectionTester).to receive(:call)
            .and_return({ success: false, error: 'Photoprism connection failed: 401' })
        end

        it 'includes error message in alerts' do
          result = service.call

          expect(result[:alerts]).to include('Photoprism connection failed: 401')
        end
      end
    end

    context 'when immich settings have not changed' do
      let(:service) { described_class.new(user, settings_params) }

      before do
        user.update(settings: { 'immich_url' => 'https://immich.test', 'immich_api_key' => 'existing-key' })
      end

      let(:settings_params) { { 'immich_url' => 'https://immich.test', 'immich_api_key' => 'existing-key' } }

      it 'does not test the immich connection' do
        expect(Immich::ConnectionTester).not_to receive(:new)

        service.call
      end
    end

    context 'when photoprism settings have not changed' do
      let(:service) { described_class.new(user, settings_params) }

      before do
        user.update(settings: { 'photoprism_url' => 'https://photoprism.test', 'photoprism_api_key' => 'existing-key' })
      end

      let(:settings_params) do
        { 'photoprism_url' => 'https://photoprism.test', 'photoprism_api_key' => 'existing-key' }
      end

      it 'does not test the photoprism connection' do
        expect(Photoprism::ConnectionTester).not_to receive(:new)

        service.call
      end
    end
  end
end
