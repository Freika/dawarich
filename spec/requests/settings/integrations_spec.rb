# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Integrations', type: :request do
  describe 'PATCH /settings/integrations' do
    let(:user) { create(:user) }
    let(:params) { { settings: { 'immich_skip_ssl_verification' => '1', 'photoprism_skip_ssl_verification' => '1' } } }

    before do
      sign_in user
      allow(Resolv).to receive(:getaddress).and_call_original
      allow(Resolv).to receive(:getaddress).with('immich.test').and_return('93.184.216.34')
      allow(Resolv).to receive(:getaddress).with('photoprism.test').and_return('93.184.216.34')
      allow(Resolv).to receive(:getaddress).with('airtrail.test').and_return('93.184.216.34')
    end

    it 'updates the user settings' do
      patch '/settings/integrations', params: params

      user.reload
      expect(user.settings['immich_skip_ssl_verification']).to eq(true)
      expect(user.settings['photoprism_skip_ssl_verification']).to eq(true)
    end

    it 'redirects back to the pane that was saved' do
      patch '/settings/integrations', params: params.merge(service: 'photoprism')

      expect(response).to redirect_to(settings_integrations_path(service: 'photoprism'))
    end

    it 'refreshes cached photos when requested' do
      Rails.cache.write("photos_#{user.id}_test", ['cached'])
      Rails.cache.write("photo_thumbnail_#{user.id}_immich_test", 'thumb')

      patch '/settings/integrations', params: params.merge(refresh_photos_cache: '1')

      expect(Rails.cache.read("photos_#{user.id}_test")).to be_nil
      expect(Rails.cache.read("photo_thumbnail_#{user.id}_immich_test")).to be_nil
    end

    context 'when immich settings change' do
      let(:immich_url) { 'https://immich.test' }
      let(:immich_api_key) { 'immich-key' }
      let(:immich_response) do
        { 'assets' => { 'items' => [{ 'id' => 'asset-id' }] } }.to_json
      end

      before do
        stub_request(:post, "#{immich_url}/api/search/metadata")
          .to_return(status: 200, body: immich_response, headers: {})
        stub_request(:get, "#{immich_url}/api/assets/asset-id/thumbnail?size=preview")
          .to_return(status: 403, body: { message: 'Missing required permission: asset.view' }.to_json)
      end

      it 'reports missing asset.view permission' do
        patch '/settings/integrations', params: {
          settings: {
            'immich_url' => immich_url,
            'immich_api_key' => immich_api_key
          }
        }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:alert]).to include('asset.view')
      end
    end

    context 'when photoprism settings change' do
      let(:photoprism_url) { 'https://photoprism.test' }
      let(:photoprism_api_key) { 'photoprism-key' }

      before do
        stub_request(:get, "#{photoprism_url}/api/v1/photos")
          .with(query: hash_including({ 'count' => '1', 'public' => 'true' }))
          .to_return(status: 200, body: [].to_json)
      end

      it 'verifies photoprism connection' do
        patch '/settings/integrations', params: {
          settings: {
            'photoprism_url' => photoprism_url,
            'photoprism_api_key' => photoprism_api_key
          }
        }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:notice]).to include('Photoprism connection verified')
      end
    end

    context 'when the airtrail host is unreachable' do
      before do
        stub_request(:get, 'https://airtrail.test/api/flight/list?scope=mine').to_raise(Errno::ECONNREFUSED)
      end

      it 'saves the settings and reports the failure instead of crashing' do
        patch '/settings/integrations', params: {
          settings: { 'airtrail_url' => 'https://airtrail.test', 'airtrail_api_key' => 'k' },
          service: 'airtrail'
        }

        expect(response).to redirect_to(settings_integrations_path(service: 'airtrail'))
        follow_redirect!
        expect(flash[:alert]).to include('AirTrail')
        expect(user.reload.settings['airtrail_connection_status']).to eq('failed')
      end
    end

    context 'when airtrail settings change' do
      let(:airtrail_url) { 'https://airtrail.test' }

      it 'persists settings and verifies the airtrail connection' do
        stub_request(:get, "#{airtrail_url}/api/flight/list?scope=mine")
          .to_return(status: 200, body: { success: true, flights: [] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        patch '/settings/integrations', params: {
          settings: { 'airtrail_url' => airtrail_url, 'airtrail_api_key' => 'k' }
        }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:notice]).to include('AirTrail connection verified')
        expect(user.reload.settings['airtrail_url']).to eq(airtrail_url)
      end

      it 'keeps malformed upstream responses within the flash cookie limit' do
        stub_request(:get, "#{airtrail_url}/api/flight/list?scope=mine")
          .to_return(status: 200, body: "<html>#{'x' * 12_000}")

        patch '/settings/integrations', params: {
          settings: { 'airtrail_url' => airtrail_url, 'airtrail_api_key' => 'k' }
        }

        expect(response).to redirect_to(settings_integrations_path)
        expect(flash[:alert]).to start_with('AirTrail connection failed:')
        expect(flash[:alert].bytesize).to be <= 512
      end
    end

    context 'when TeslaMateApi settings change' do
      let(:teslamate_url) { 'https://teslamate.test' }

      before do
        allow(Resolv).to receive(:getaddress).with('teslamate.test').and_return('93.184.216.34')
      end

      it 'persists settings and verifies the cars endpoint' do
        stub_request(:get, "#{teslamate_url}/api/v1/cars")
          .to_return(status: 200, body: { data: { cars: [] } }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        patch '/settings/integrations', params: {
          settings: {
            'teslamate_url' => teslamate_url,
            'teslamate_username' => 'proxy-user',
            'teslamate_password' => 'proxy-password',
            'teslamate_api_token' => 'proxy-token',
            'teslamate_skip_ssl_verification' => '1'
          },
          service: 'teslamate'
        }

        expect(response).to redirect_to(settings_integrations_path(service: 'teslamate'))
        follow_redirect!
        expect(flash[:notice]).to include('TeslaMateApi connection verified')
        expect(user.reload.settings).to include(
          'teslamate_url' => teslamate_url,
          'teslamate_username' => 'proxy-user',
          'teslamate_password' => 'proxy-password',
          'teslamate_api_token' => 'proxy-token',
          'teslamate_skip_ssl_verification' => true,
          'teslamate_connection_status' => 'ok'
        )
      end
    end

    context 'when user is on Lite plan (Cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update_column(:plan, User.plans[:lite])
      end

      it 'redirects with pro required alert on update' do
        patch '/settings/integrations', params: params

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Pro plan')
      end

      it 'shows upgrade prompt on index page' do
        get '/settings/integrations'

        expect(response.body).to include('Upgrade to Pro')
        expect(response.body).to include('Immich')
      end
    end

    context 'when self-hosted Lite user (bypasses gate)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        user.update_column(:plan, User.plans[:lite])
      end

      it 'allows integration settings update' do
        patch '/settings/integrations', params: params

        expect(response).to redirect_to(settings_integrations_path)
      end
    end

    context 'when user is inactive' do
      before do
        user.update(status: :inactive, active_until: 1.day.ago)
      end

      it 'redirects to the root path' do
        patch '/settings/integrations', params: params

        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Your account is not active.')
      end
    end
  end

  describe 'GET /settings/integrations' do
    let(:user) { create(:user) }

    before { sign_in user }

    def sidebar_link(body, service)
      body[/<a[^>]*data-testid="integration-#{service}"[^>]*>/]
    end

    it 'lists every service in the sidebar on self-hosted instances' do
      get settings_integrations_path

      %w[geocoding immich photoprism airtrail].each do |service|
        expect(response.body).to include(%(data-testid="integration-#{service}"))
      end
    end

    it 'hides geocoding from the sidebar on non-self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

      get settings_integrations_path

      expect(response.body).not_to include('data-testid="integration-geocoding"')
      expect(response.body).to include('data-testid="integration-immich"')
    end

    it 'marks a service as connected after a successful connection' do
      user.update!(settings: user.settings.merge('immich_url' => 'https://immich.test',
                                                 'immich_api_key' => 'key',
                                                 'immich_connection_status' => 'ok'))

      get settings_integrations_path

      expect(sidebar_link(response.body, 'immich')).to include('data-status="connected"')
    end

    it 'marks a configured service as failed after a failed connection' do
      user.update!(settings: user.settings.merge('airtrail_url' => 'https://airtrail.test',
                                                 'airtrail_api_key' => 'key',
                                                 'airtrail_connection_status' => 'failed'))

      get settings_integrations_path

      expect(sidebar_link(response.body, 'airtrail')).to include('data-status="failed"')
    end

    it 'shows no status for an unconfigured service' do
      get settings_integrations_path

      expect(sidebar_link(response.body, 'photoprism')).not_to include('data-status')
    end

    it 'renders the pane for the selected service' do
      get settings_integrations_path(service: 'photoprism')

      expect(response.body).to include('name="settings[photoprism_url]"')
      expect(response.body).not_to include('name="settings[immich_url]"')
    end

    it 'renders the TeslaMateApi settings pane' do
      get settings_integrations_path(service: 'teslamate')

      expect(response.body).to include('name="settings[teslamate_url]"')
      expect(response.body).to include('TeslaMateApi Integration')
      expect(response.body).to include('https://github.com/tobiasehlert/teslamateapi#how-to-run-it')
      expect(response.body).to include('man-in-the-middle attacks')
    end

    it 'falls back to the first available service for unknown service params' do
      get settings_integrations_path(service: 'bogus')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('settings.geocoding.show.provider'))
    end
  end
end
