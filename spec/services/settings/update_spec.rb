# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Settings::Update do
  let(:user) { create(:user) }

  before do
    stub_host_addresses('immich.test', '93.184.216.34')
    stub_host_addresses('photoprism.test', '93.184.216.34')
    stub_host_addresses('airtrail.test', '93.184.216.34')
  end

  # The connection testers are exercised for real; only the integration
  # servers are stubbed.
  def stub_immich_search(status: 200)
    stub_request(:post, 'https://immich.test/api/search/metadata')
      .to_return(status:, body: { assets: { items: [] } }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_photoprism_photos(status: 200)
    stub_request(:get, 'https://photoprism.test/api/v1/photos')
      .with(query: hash_including({}))
      .to_return(status:, body: '[]', headers: { 'Content-Type' => 'application/json' })
  end

  describe '#call' do
    context 'when airtrail settings change' do
      let(:settings_params) do
        ActionController::Parameters.new(airtrail_url: 'https://airtrail.test', airtrail_api_key: 'k').permit!
      end
      let(:service) { described_class.new(user, settings_params) }

      it 'tests the AirTrail connection and reports the result' do
        stub_request(:get, 'https://airtrail.test/api/flight/list?scope=mine')
          .to_return(status: 200, body: { success: true, flights: [] }.to_json)

        result = service.call

        expect(result[:notices]).to include('AirTrail connection verified')
        expect(user.reload.settings['airtrail_url']).to eq('https://airtrail.test')
      end
    end

    context 'when the TeslaMateApi URL changes' do
      let(:settings_params) { { 'teslamate_url' => 'https://teslamate-new.test' } }
      let(:service) { described_class.new(user, settings_params) }

      before do
        user.update!(settings: user.settings.merge(
          'teslamate_url' => 'https://teslamate-old.test',
          'teslamate_last_synced_at' => '2026-09-01T12:00:00Z',
          'teslamate_last_synced_url' => 'https://teslamate-old.test',
          'teslamate_processing_pending' => true,
          'teslamate_processing_pending_url' => 'https://teslamate-old.test'
        ))
        stub_host_addresses('teslamate-new.test', '93.184.216.34')
        stub_request(:get, 'https://teslamate-new.test/api/v1/cars')
          .to_return(status: 200, body: { data: { cars: [] } }.to_json)
      end

      it 'clears the previous source checkpoint' do
        service.call

        settings = user.reload.settings
        expect(settings['teslamate_url']).to eq('https://teslamate-new.test')
        expect(settings['teslamate_last_synced_at']).to be_nil
        expect(settings['teslamate_last_synced_url']).to be_nil
        expect(settings['teslamate_processing_pending']).to be(false)
        expect(settings['teslamate_processing_pending_url']).to be_nil
      end
    end

    context 'when updating basic settings' do
      let(:settings_params) { { 'immich_url' => 'https://immich.test', 'photoprism_url' => 'https://photoprism.test' } }
      let(:service) { described_class.new(user, settings_params) }

      it 'updates the user settings' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:notices]).to include('Settings updated')
        expect(user.reload.settings['immich_url']).to eq('https://immich.test')
        expect(user.reload.settings['photoprism_url']).to eq('https://photoprism.test')
      end
    end

    context 'when user update fails' do
      let(:settings_params) { { 'immich_url' => 'https://immich.test' } }
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
      let(:settings_params) { { 'immich_url' => 'https://immich.test' } }
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
          stub_immich_search
        end

        it 'includes success message in notices' do
          result = service.call

          expect(result[:notices]).to include('Immich connection verified')
          expect(result[:alerts]).to be_empty
        end

        it 'records the successful connection status' do
          service.call

          expect(user.reload.settings['immich_connection_status']).to eq('ok')
        end
      end

      context 'when connection test fails' do
        before do
          stub_immich_search(status: 500)
        end

        it 'includes error message in alerts' do
          result = service.call

          expect(result[:alerts]).to include('Immich connection failed: 500')
        end

        it 'records the failed connection status' do
          service.call

          expect(user.reload.settings['immich_connection_status']).to eq('failed')
        end
      end
    end

    context 'when photoprism settings change' do
      let(:settings_params) { { 'photoprism_url' => 'https://photoprism.test', 'photoprism_api_key' => 'new-key' } }
      let(:service) { described_class.new(user, settings_params) }

      context 'when connection test succeeds' do
        before do
          stub_photoprism_photos
        end

        it 'includes success message in notices' do
          result = service.call

          expect(result[:notices]).to include('Photoprism connection verified')
          expect(result[:alerts]).to be_empty
        end
      end

      context 'when connection test fails' do
        before do
          stub_photoprism_photos(status: 401)
        end

        it 'includes error message in alerts' do
          result = service.call

          expect(result[:alerts]).to include('Photoprism connection failed: 401')
        end
      end
    end

    context 'when another process writes settings during the connection test' do
      let(:settings_params) { { 'immich_url' => 'https://immich.test', 'immich_api_key' => 'new-key' } }
      let(:service) { described_class.new(user, settings_params) }

      before do
        stub_request(:post, 'https://immich.test/api/search/metadata').to_return do
          concurrent_user = User.find(user.id)
          concurrent_user.update!(settings: concurrent_user.settings.merge('concurrent_key' => 'kept'))
          { status: 200, body: { assets: { items: [] } }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end
      end

      it 'does not clobber the concurrent write' do
        service.call

        expect(user.reload.settings['concurrent_key']).to eq('kept')
        expect(user.settings['immich_url']).to eq('https://immich.test')
        expect(user.settings['immich_connection_status']).to eq('ok')
      end
    end

    context 'when only the ssl verification toggle changes' do
      let(:settings_params) { { 'immich_skip_ssl_verification' => '1' } }
      let(:service) { described_class.new(user, settings_params) }

      before do
        user.update(settings: { 'immich_url' => 'https://immich.test', 'immich_api_key' => 'existing-key' })
        stub_immich_search
      end

      it 'retests the connection and refreshes the recorded status' do
        result = service.call

        expect(result[:notices]).to include('Immich connection verified')
        expect(user.reload.settings['immich_connection_status']).to eq('ok')
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

      it 'does not record a connection status' do
        service.call

        expect(user.reload.settings['immich_connection_status']).to be_nil
      end
    end

    context 'when not self-hosted and URL points to a blocked address' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        stub_host_addresses('169.254.169.254', '169.254.169.254')
      end

      let(:settings_params) { { 'immich_url' => 'http://169.254.169.254/latest' } }
      let(:service) { described_class.new(user, settings_params) }

      it 'rejects the URL and returns failure' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:alerts].first).to include('not allowed')
      end

      it 'does not update the settings' do
        service.call

        expect(user.reload.settings['immich_url']).to be_nil
      end
    end

    context 'when self-hosted and URL points to a private address' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      let(:settings_params) { { 'immich_url' => 'http://127.0.0.1:2283' } }
      let(:service) { described_class.new(user, settings_params) }

      it 'allows the URL' do
        result = service.call

        expect(result[:success]).to be true
        expect(user.reload.settings['immich_url']).to eq('http://127.0.0.1:2283')
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
