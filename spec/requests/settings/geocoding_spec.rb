# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::Geocoding', type: :request do
  def photon_rps_field(body)
    body.scan(/<input[^>]*>/).find { |tag| tag.include?('name="photon[rps]"') }
  end

  let(:user) { create(:user) }

  let(:photon_body) do
    {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature',
          properties: { city: 'Leipzig', country: 'Germany', name: 'Testplatz' },
          geometry: { type: 'Point', coordinates: [12.3712, 51.3402] } }
      ]
    }.to_json
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
    allow(Resolv).to receive(:getaddress).and_return('203.0.113.10')
    allow(Socket).to receive(:getaddrinfo).and_return([])
    sign_in user
  end

  describe 'GET /settings/geocoding' do
    it 'redirects the old geocoding settings path to the integrations pane' do
      get settings_geocoding_path

      expect(response).to redirect_to(settings_integrations_path(service: 'geocoding'))
    end

    it 'renders the provider settings page' do
      get settings_integrations_path(service: 'geocoding')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('settings.geocoding.show.provider'))
    end

    it 'is not available on non-self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

      get settings_integrations_path(service: 'geocoding')

      expect(response.body).not_to include('data-testid="integration-geocoding"')
      expect(response.body).not_to include(I18n.t('settings.geocoding.show.provider'))
    end

    it 'never echoes a stored api key' do
      row = create(:service_setting, :geoapify, :active, user: user, api_key: 'super-secret-key-value')

      get settings_integrations_path(service: 'geocoding')

      expect(row.api_key).to eq('super-secret-key-value')
      expect(response.body).not_to include('super-secret-key-value')
    end

    it 'shows the ENV-managed banner when ENV is set' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)

      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include(I18n.t('settings.geocoding.show.env_managed_notice'))
    end

    it 'does not show the ENV-managed banner without ENV' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).not_to include(I18n.t('settings.geocoding.show.env_managed_notice'))
    end

    it 'lists geocoding in the integrations sidebar' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include('data-testid="integration-geocoding"')
      expect(response.body).to include(I18n.t('settings.integrations.index.services.geocoding'))
    end

    def photon_host_input(body)
      body.scan(/<input[^>]*>/).find { |tag| tag.include?('name="photon[host]"') }
    end

    it 'prefills the photon host with ChibiGeo for fresh users' do
      get settings_integrations_path(service: 'geocoding')

      expect(photon_host_input(response.body)).to include('value="app.chibigeo.com/v1/photon"')
    end

    it 'keeps a saved custom photon host instead of the ChibiGeo default' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      get settings_integrations_path(service: 'geocoding')

      input = photon_host_input(response.body)
      expect(input).to include('value="photon.mine.example.com"')
      expect(input).not_to include('app.chibigeo.com')
    end

    it 'offers an explicit three-way photon host choice with ChibiGeo preselected for fresh users' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include(I18n.t('settings.geocoding.show.choice_chibigeo'))
      expect(response.body).to include(I18n.t('settings.geocoding.show.choice_komoot'))
      expect(response.body).to include(I18n.t('settings.geocoding.show.choice_custom'))
      expect(response.body).to include(I18n.t('settings.geocoding.show.recommended'))
      expect(response.body).to match(/value="chibigeo"[^>]*checked/)
    end

    it 'preselects the custom host choice when a custom host is saved' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to match(/value="custom"[^>]*checked/)
    end

    it 'preselects the komoot choice when the komoot host is saved' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.komoot.io' })

      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to match(/value="komoot"[^>]*checked/)
    end

    it 'locks the HTTPS toggle for https-only hosts' do
      get settings_integrations_path(service: 'geocoding')

      toggle = response.body.scan(/<input[^>]*>/).find do |tag|
        tag.include?('name="photon[use_https]"') && tag.include?('type="checkbox"')
      end
      expect(toggle).to include('checked')
      expect(toggle).to include('disabled')
      expect(response.body).to include(I18n.t('settings.geocoding.show.https_locked'))
    end

    it 'leaves the HTTPS toggle adjustable for custom hosts' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      get settings_integrations_path(service: 'geocoding')

      toggle = response.body.scan(/<input[^>]*>/).find do |tag|
        tag.include?('name="photon[use_https]"') && tag.include?('type="checkbox"')
      end
      expect(toggle).to be_present
      expect(toggle).not_to include('disabled')
    end

    it 'locks the rate field to one request per second on the komoot host' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.komoot.io' })

      get settings_integrations_path(service: 'geocoding')

      field = photon_rps_field(response.body)
      expect(field).to include('disabled')
      expect(field).to include('value="1.0"')
      expect(response.body).to include(I18n.t('settings.geocoding.show.rps_hint_komoot'))
    end

    it 'offers the ChibiGeo plan range and starts on the free tier' do
      get settings_integrations_path(service: 'geocoding')

      field = photon_rps_field(response.body)
      expect(field).not_to include('disabled')
      expect(field).to include('min="1.0"')
      expect(field).to include('max="25.0"')
      expect(response.body).to include(I18n.t('settings.geocoding.show.rps_hint_chibigeo'))
    end

    it 'leaves the rate open and unset for a custom host' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })

      get settings_integrations_path(service: 'geocoding')

      field = photon_rps_field(response.body)
      expect(field).not_to include('disabled')
      expect(field).not_to include('value=')
      expect(response.body).to include(I18n.t('settings.geocoding.show.rps_hint_custom'))
    end

    it 'shows the saved rate' do
      create(:service_setting, :active, user: user,
                                        config: { 'host' => 'photon.mine.example.com', 'rps' => 7 })

      get settings_integrations_path(service: 'geocoding')

      expect(photon_rps_field(response.body)).to include('value="7.0"')
    end

    it 'offers a rate field for the other providers too' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include('name="nominatim[rps]"')
      expect(response.body).to include('name="geoapify[rps]"')
      expect(response.body).to include('name="locationiq[rps]"')
    end

    it 'offers a free ChibiGeo API key with a UTM-tagged link and the plan limits' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include('utm_source=dawarich')
      expect(response.body).to include(I18n.t('settings.geocoding.show.chibigeo_limits'))
      expect(response.body).to include(I18n.t('settings.geocoding.show.chibigeo_key_link'))
    end

    it 'carries both the ChibiGeo panel and the komoot warning in the photon fieldset' do
      get settings_integrations_path(service: 'geocoding')

      expect(response.body).to include('data-geocoding-settings-target="chibigeoPanel"')
      expect(response.body).to include('data-geocoding-settings-target="komootWarning"')
    end

    it 'renders even when stored credentials cannot be decrypted' do
      row = create(:service_setting, :geoapify, :active, user: user)
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = 'garbage' WHERE id = #{row.id}"
      )

      get settings_integrations_path(service: 'geocoding')

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /settings/geocoding' do
    it 'creates and activates a photon setting' do
      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.mine.example.com', use_https: '1', api_key: 'new-key' }
      }

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row.active).to be(true)
      expect(row.host).to eq('photon.mine.example.com')
      expect(row.use_https).to be(true)
      expect(row.api_key).to eq('new-key')
    end

    it 'keeps the stored api key when the field is blank' do
      create(:service_setting, :geoapify, :active, user: user, api_key: 'keep-me')

      patch settings_geocoding_path, params: { provider: 'geoapify', geoapify: { api_key: '' } }

      expect(user.service_settings.service_geocoding.find_by(provider: 'geoapify').api_key).to eq('keep-me')
    end

    it 'clears an optional api key when requested' do
      create(:service_setting, :active, user: user, api_key: 'old-key')

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.example.com', clear_api_key: '1' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').api_key).to be_nil
    end

    it 'clears the recorded connection status when the configuration changes' do
      create(:service_setting, :active, user: user,
                               config: { 'host' => 'photon.mine.example.com', 'connection_status' => 'ok' })

      patch settings_geocoding_path, params: { provider: 'photon', photon: { host: 'photon.other.example.com' } }

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row.config['connection_status']).to be_nil
    end

    it 'keeps the recorded connection status when nothing changes' do
      create(:service_setting, :active, user: user,
                               config: { 'host' => 'photon.mine.example.com', 'connection_status' => 'ok' })

      patch settings_geocoding_path, params: { provider: 'photon', photon: { host: 'photon.mine.example.com' } }

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row.config['connection_status']).to eq('ok')
    end

    it 'saves a custom rate limit' do
      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.mine.example.com', rps: '4' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').rps).to eq(4.0)
    end

    it 'reads a blank rate as unlimited' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com', 'rps' => 4 })

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.mine.example.com', rps: '' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').rps).to be_nil
    end

    it 'clamps a submitted chibigeo rate to the top public plan' do
      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'app.chibigeo.com/v1/photon', rps: '100', api_key: 'ck_test' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').rps).to eq(25.0)
    end

    it 'pins komoot to one request per second even when the form is tampered with' do
      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.komoot.io', rps: '50' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').rps).to eq(1.0)
    end

    it 'keeps the recorded connection status when the rate is re-submitted unchanged' do
      create(:service_setting, :active, user: user,
                               config: { 'host' => 'photon.mine.example.com', 'rps' => 4,
                                         'connection_status' => 'ok' })

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.mine.example.com', rps: '4.0' }
      }

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row.config['connection_status']).to eq('ok')
    end

    it 'clears the recorded connection status when the rate changes' do
      create(:service_setting, :active, user: user,
                               config: { 'host' => 'photon.mine.example.com', 'rps' => 4,
                                         'connection_status' => 'ok' })

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.mine.example.com', rps: '9' }
      }

      row = user.service_settings.service_geocoding.find_by(provider: 'photon')
      expect(row.config['connection_status']).to be_nil
    end

    it 'switches the active provider while keeping stored credentials' do
      create(:service_setting, :geoapify, :active, user: user, api_key: 'geo-key')

      patch settings_geocoding_path, params: { provider: 'photon', photon: { host: 'photon.example.com' } }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').active).to be(true)
      geoapify = user.service_settings.service_geocoding.find_by(provider: 'geoapify')
      expect(geoapify.active).to be(false)
      expect(geoapify.api_key).to eq('geo-key')
    end

    it 'deactivates everything when disabled is selected' do
      create(:service_setting, :active, user: user)

      patch settings_geocoding_path, params: { provider: 'disabled' }

      expect(user.service_settings.service_geocoding.where(active: true)).to be_empty
    end

    it 'reports validation errors without saving' do
      patch settings_geocoding_path, params: { provider: 'photon', photon: { host: '' } }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon')).to be_nil
      expect(flash[:alert]).to be_present
    end

    it 'rejects unknown providers' do
      patch settings_geocoding_path, params: { provider: 'osm' }

      expect(user.service_settings.count).to eq(0)
      expect(flash[:alert]).to be_present
    end

    it 'rejects a host on the cloud metadata address without saving' do
      allow(Resolv).to receive(:getaddress).with('169.254.169.254').and_return('169.254.169.254')

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: '169.254.169.254' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon')).to be_nil
      expect(flash[:alert]).to be_present
    end

    it 'rejects a hostname that resolves into a blocked range' do
      allow(Resolv).to receive(:getaddress).with('metadata.internal.example').and_return('169.254.169.254')

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'metadata.internal.example' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon')).to be_nil
      expect(flash[:alert]).to be_present
    end

    it 'rejects a blocked nominatim host as well' do
      allow(Resolv).to receive(:getaddress).with('169.254.169.254').and_return('169.254.169.254')

      patch settings_geocoding_path, params: {
        provider: 'nominatim',
        nominatim: { host: '169.254.169.254' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'nominatim')).to be_nil
    end

    it 'saves a host the web container cannot resolve' do
      allow(Resolv).to receive(:getaddress).with('photon.homelab.lan').and_raise(Resolv::ResolvError)
      allow(Socket).to receive(:getaddrinfo).with('photon.homelab.lan', nil).and_raise(SocketError)

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: 'photon.homelab.lan' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon').active).to be(true)
    end

    it 'rejects a decimal-form IPv4 host' do
      allow(Resolv).to receive(:getaddress).with('2130706433').and_raise(Resolv::ResolvError)

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: '2130706433' }
      }

      expect(user.service_settings.service_geocoding.find_by(provider: 'photon')).to be_nil
      expect(flash[:alert]).to be_present
    end

    it 'calls a blocked numeric host blocked rather than unresolvable' do
      allow(Resolv).to receive(:getaddress).with('2130706433').and_raise(Resolv::ResolvError)

      patch settings_geocoding_path, params: {
        provider: 'photon',
        photon: { host: '2130706433' }
      }

      expect(flash[:alert]).to include(I18n.t('services.concerns.url_validatable.blocked_address'))
      expect(flash[:alert]).not_to include('2130706433')
    end
  end

  describe 'POST /settings/geocoding/test' do
    before do
      allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
    end

    it 'reports the resolved place for a working provider' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Leipzig')
    end

    it 'records a successful test on the active setting' do
      setting = create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(setting.reload.config['connection_status']).to eq('ok')
    end

    it 'reports a failure when the provider times out' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse}).to_timeout

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Geocoder')
    end

    it 'records a failed test on the active setting' do
      setting = create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse}).to_timeout

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(setting.reload.config['connection_status']).to eq('failed')
    end

    it 'reports missing configuration' do
      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include(I18n.t('settings.geocoding.test.not_configured'))
    end

    it 'reports a busy rate limit without failing the connection test' do
      setting = create(:service_setting, :active, user: user,
                                                  config: { 'host' => 'photon.mine.example.com',
                                                            'connection_status' => 'ok' })
      allow(Geocoding::Search).to receive(:with_config)
        .with(hash_including(max_wait: Settings::GeocodingController::TEST_MAX_WAIT))
        .and_return(nil)

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('rate limit is busy right now')
      expect(setting.reload.config['connection_status']).to eq('ok')
    end

    it 'keeps the detail of a connection failure in the flash' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      allow(Geocoding::Search).to receive(:with_config)
        .and_raise(SocketError, 'getaddrinfo: Name or service not known')

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('getaddrinfo')
    end

    it 'does not leak details of an unexpected failure into the flash' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      allow(Geocoding::Search).to receive(:with_config)
        .and_raise(RuntimeError, 'PG::ConnectionBad at 10.0.0.5')

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response.body).to include('RuntimeError')
      expect(response.body).not_to include('10.0.0.5')
    end

    it 'tests the user row even when ENV is set' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/reverse})
        .to_return(status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' })

      post test_settings_geocoding_path, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(WebMock).to have_requested(:get, %r{https://photon\.mine\.example\.com/reverse})
    end
  end
end
