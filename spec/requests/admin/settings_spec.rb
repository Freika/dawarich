# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Settings' do
  let(:admin) { create(:user, admin: true) }
  let(:non_admin) { create(:user) }

  around do |example|
    saved = %w[PHOTON_API_HOST ATLAS_URL MAP_MATCHING_ENABLED].index_with { |key| ENV.fetch(key, nil) }
    ENV['PHOTON_API_HOST'] = nil
    ENV['ATLAS_URL'] = nil
    ENV['MAP_MATCHING_ENABLED'] = nil
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    saved.each { |key, value| ENV[key] = value }
    InstanceSettings::Resolver.reset!
  end

  describe 'authorisation' do
    it 'does not serve the page to a non-admin' do
      sign_in non_admin

      get '/admin/settings'

      expect(response).not_to have_http_status(:ok)
    end

    it 'serves the page to an admin' do
      sign_in admin

      get '/admin/settings'

      expect(response).to have_http_status(:ok)
    end

    it 'refuses a settings write from a non-admin' do
      sign_in non_admin

      patch '/admin/settings', params: { instance_settings: { photon_api_host: 'attempt.example.com' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
    end

    it 'does not serve the page on a cloud instance, even to an admin' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      sign_in admin

      get '/admin/settings'

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'GET show' do
    before { sign_in admin }

    it 'renders a pinned setting as disabled and names the variable pinning it' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).to include('PHOTON_API_HOST')
      expect(response.body).to match(/<input[^>]*id="instance_settings_photon_api_host"[^>]*\sdisabled[\s>]/)
    end

    # Differential: proves the assertion above is about pinning, not about every
    # field happening to carry the attribute.
    it 'leaves an unpinned field editable' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'nominatim' }

      expect(response.body).to include('id="instance_settings_nominatim_api_host"')
      expect(response.body).not_to match(/<input[^>]*id="instance_settings_nominatim_api_host"[^>]*\sdisabled[\s>]/)
    end

    it 'never renders a stored secret into the page' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'super-secret-value')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).not_to include('super-secret-value')
    end
  end

  describe 'sections' do
    before { sign_in admin }

    def section_link(name)
      response.body[/<a[^>]*data-testid="instance-settings-section-#{name}"[^>]*>/]
    end

    it 'switches sections inside a frame that advances the URL, keeping the page scroll' do
      get '/admin/settings'

      frame = response.body[%r{<turbo-frame[^>]*id="instance-settings-sections"[^>]*>.*</turbo-frame>}m]
      expect(frame).to be_present
      expect(frame[/<turbo-frame[^>]*>/]).to include('data-turbo-action="advance"')
      expect(frame).to include('data-testid="instance-settings-section-geoapify"')
      expect(frame).to include('data-testid="instance-settings-pane-photon"')
    end

    it 'saves a section with a full page visit so the flash and geocoding status refresh' do
      get '/admin/settings'

      form = response.body[%r{<form[^>]*action="/admin/settings"[^>]*>}]
      expect(form).to include('data-turbo-frame="_top"')
    end

    it 'lists every section in the navigation' do
      get '/admin/settings'

      %w[photon geoapify nominatim locationiq rate_limit points map_matching].each do |name|
        expect(section_link(name)).to be_present, "missing #{name} in the section navigation"
      end
    end

    it 'opens the section of the provider in use' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'key')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(section_link('geoapify')).to include('aria-current="page"')
      expect(response.body).to include('id="instance_settings_geoapify_api_key"')
      expect(response.body).not_to include('id="instance_settings_photon_api_host"')
    end

    it 'opens Photon when no provider is configured' do
      get '/admin/settings'

      expect(section_link('photon')).to include('aria-current="page"')
    end

    it 'renders only the fields of the requested section' do
      get '/admin/settings', params: { section: 'points' }

      expect(response.body).to include('id="instance_settings_store_geodata"')
      expect(response.body).not_to include('id="instance_settings_photon_api_host"')
      expect(response.body).not_to include('id="instance_settings_reverse_geocoding_rps"')
    end

    it 'shows map matching as an instance-wide setting with a visual example and privacy disclosure' do
      get '/admin/settings', params: { section: 'map_matching' }

      expect(response.body).to include('id="instance_settings_atlas_url"')
      expect(response.body).to include('id="instance_settings_map_matching_enabled"')
      expect(response.body).to include('data-testid="map-matching-example"')
      expect(response.body).to include('map_matching_example-')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t('admin.settings.show.map_matching.privacy')))
    end

    it 'falls back to the default section for an unknown one' do
      get '/admin/settings', params: { section: 'bogus' }

      expect(response).to have_http_status(:ok)
      expect(section_link('photon')).to include('aria-current="page"')
    end

    it 'returns to the section that was saved' do
      patch '/admin/settings', params: { section: 'nominatim',
                                         instance_settings: { nominatim_api_host: 'nominatim.example.com' } }

      expect(response).to redirect_to(admin_settings_path(section: 'nominatim'))
    end

    it 'marks a section whose value the environment pins' do
      ENV['NOMINATIM_API_KEY'] = 'env-key'
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(section_link('nominatim')).to include('data-status="pinned"')
      expect(section_link('geoapify')).not_to include('data-status')
    end

    it 'offers no save button in a section the environment pins entirely' do
      ENV['GEOAPIFY_API_KEY'] = 'env-key'
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'geoapify' }

      pane = response.body[/data-testid="instance-settings-pane-geoapify".*/m]
      expect(pane).not_to include(I18n.t('admin.settings.show.save'))
    end

    it 'keeps the save button in a section with an editable value' do
      get '/admin/settings', params: { section: 'geoapify' }

      pane = response.body[/data-testid="instance-settings-pane-geoapify".*/m]
      expect(pane).to include(I18n.t('admin.settings.show.save'))
    end

    it 'marks a section holding a secret that cannot be decrypted' do
      setting = InstanceSetting.create!(key: 'locationiq_api_key', value: 'token')
      InstanceSetting.connection.execute(
        "UPDATE instance_settings SET encrypted_value = 'not-valid-ciphertext' WHERE id = #{setting.id}"
      )
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(section_link('locationiq')).to include('data-status="attention"')
    end
  end

  describe 'PATCH update' do
    before { sign_in admin }

    it 'persists a setting that no variable pins' do
      patch '/admin/settings', params: { instance_settings: { photon_api_host: 'stored.example.com' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('stored.example.com')
    end

    # A disabled input is a UI affordance, not a control: the server has to
    # refuse the write too, or the panel is back to accepting input it discards.
    it 'refuses to write a pinned setting even when the form posts it' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      patch '/admin/settings', params: { instance_settings: { photon_api_host: 'attempt.example.com' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
    end

    it 'ignores a key the registry does not declare' do
      patch '/admin/settings', params: { instance_settings: { not_a_setting: 'x' } }

      expect(InstanceSetting.find_by(key: 'not_a_setting')).to be_nil
      expect(response).not_to have_http_status(:internal_server_error)
    end

    it 'stores a secret in the encrypted column' do
      patch '/admin/settings', params: { instance_settings: { geoapify_api_key: 'a-key' } }

      raw = InstanceSetting.connection.select_value(
        "SELECT encrypted_value FROM instance_settings WHERE key = 'geoapify_api_key'"
      )
      expect(raw).to be_present
      expect(raw).not_to include('a-key')
    end
  end

  describe 'geocoding input' do
    before { sign_in admin }

    it 'stores a pasted URL as a bare host' do
      patch '/admin/settings', params: { instance_settings: { photon_api_host: ' https://Photon.Example.com:2322/ ' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('photon.example.com:2322')
    end

    it 'turns HTTPS on for a TLS-only host pasted with its scheme' do
      patch '/admin/settings',
            params: { instance_settings: { photon_api_host: 'https://app.chibigeo.com/v1/photon',
                                           photon_api_key: 'chibi-key', photon_api_use_https: 'false' } }

      config = Geocoding::Config.resolved_config
      expect(config.host).to eq('app.chibigeo.com/v1/photon')
      expect(config.use_https).to be(true)
    end

    it 'refuses a host that is not a bare hostname' do
      patch '/admin/settings', params: { instance_settings: { nominatim_api_host: 'nominatim example.com' } }

      expect(InstanceSetting.find_by(key: 'nominatim_api_host')).to be_nil
      expect(flash[:alert]).to eq(I18n.t('admin.settings.update.host_invalid'))
    end

    it 'does not keep a Photon key for the public komoot host' do
      InstanceSetting.create!(key: 'photon_api_key', value: 'meant-for-another-host')
      InstanceSettings::Resolver.reset!

      patch '/admin/settings',
            params: { instance_settings: { photon_api_host: 'photon.komoot.io', photon_api_key: '' } }

      expect(InstanceSettings::Resolver.value(:photon_api_key)).to be_nil
    end

    it 'refuses a ChibiGeo host without an API key' do
      patch '/admin/settings',
            params: { instance_settings: { photon_api_host: 'app.chibigeo.com/v1/photon', photon_api_key: '' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
      expect(flash[:alert]).to eq(I18n.t('admin.settings.update.chibigeo_key_required'))
    end

    it 'accepts a ChibiGeo host with an API key' do
      patch '/admin/settings',
            params: { instance_settings: { photon_api_host: 'app.chibigeo.com/v1/photon',
                                           photon_api_key: 'chibi-key' } }

      expect(InstanceSettings::Resolver.value(:photon_api_host)).to eq('app.chibigeo.com/v1/photon')
      expect(InstanceSettings::Resolver.value(:photon_api_key)).to eq('chibi-key')
    end

    it 'links the ChibiGeo guide for self-hosted geocoding' do
      get '/admin/settings', params: { section: 'photon' }

      expect(response.body).to include('https://chibigeo.com/docs/guides/dawarich-self-hosted-geocoding?')
    end
  end

  describe 'map matching input' do
    before { sign_in admin }

    it 'stores a valid Atlas URL and enables map matching' do
      patch '/admin/settings', params: {
        section: 'map_matching',
        instance_settings: { atlas_url: 'http://atlas:4567/', map_matching_enabled: 'true' }
      }

      expect(InstanceSettings::Resolver.value(:atlas_url)).to eq('http://atlas:4567')
      expect(InstanceSettings::Resolver.value(:map_matching_enabled)).to be(true)
    end

    it 'does not enable map matching without an Atlas URL' do
      patch '/admin/settings', params: {
        section: 'map_matching',
        instance_settings: { atlas_url: '', map_matching_enabled: 'true' }
      }

      expect(InstanceSettings::Resolver.value(:map_matching_enabled)).to be(false)
      expect(flash[:alert]).to eq(I18n.t('admin.settings.update.atlas_url_required'))
    end

    it 'rejects credentials embedded in the Atlas URL' do
      patch '/admin/settings', params: {
        section: 'map_matching',
        instance_settings: { atlas_url: 'https://user:secret@atlas.example.com' }
      }

      expect(InstanceSetting.find_by(key: 'atlas_url')).to be_nil
      expect(flash[:alert]).to eq(I18n.t('admin.settings.update.atlas_url_invalid'))
    end

    it 'renders environment-pinned settings as disabled' do
      ENV['ATLAS_URL'] = 'https://atlas.example.com'
      ENV['MAP_MATCHING_ENABLED'] = 'true'
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'map_matching' }

      expect(response.body).to match(/<input[^>]*id="instance_settings_atlas_url"[^>]*\sdisabled[\s>]/)
      expect(response.body).to match(/<input[^>]*id="instance_settings_map_matching_enabled"[^>]*\sdisabled[\s>]/)
    end
  end

  describe 'per-user geocoding left behind by an upgrade' do
    before { sign_in admin }

    it 'tells the admin that per-user settings were not carried over' do
      create(:service_setting, :active, user: non_admin)

      get '/admin/settings'

      expect(response.body).to include(ERB::Util.html_escape(I18n.t('admin.settings.show.geocoding.legacy_user_settings')))
    end

    it 'drops the notice once the instance has a provider' do
      create(:service_setting, :active, user: non_admin)
      configure_instance_geocoding

      get '/admin/settings'

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t('admin.settings.show.geocoding.legacy_user_settings')))
    end
  end

  describe 'review regressions' do
    before { sign_in admin }

    # Secrets are never rendered back, so the browser posts "" for any key the
    # operator did not touch. Treating that as a value erased every stored key
    # on any save — editing the Photon host wiped the Geoapify key.
    it 'keeps a stored secret when the form posts it back empty' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'must-survive')
      InstanceSettings::Resolver.reset!

      patch '/admin/settings',
            params: { instance_settings: { geoapify_api_key: '', photon_api_host: 'edited.example.com' } }

      expect(InstanceSetting.find_by(key: 'geoapify_api_key')&.value).to eq('must-survive')
      expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('edited.example.com')
    end

    it 'clears a stored secret when the operator ticks the clear box' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'remove-me')
      InstanceSettings::Resolver.reset!

      patch '/admin/settings',
            params: { instance_settings: { geoapify_api_key: '' },
                      instance_settings_clear: { geoapify_api_key: '1' } }

      expect(InstanceSetting.find_by(key: 'geoapify_api_key')&.value).to be_nil
    end

    it 'offers the clear affordance only for a stored, unpinned secret' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'stored')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).to include('instance_settings_clear[geoapify_api_key]')
      expect(response.body).not_to include('instance_settings_clear[locationiq_api_key]')
    end

    it 'still clears a secret when the operator explicitly submits a new one' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'old-key')
      InstanceSettings::Resolver.reset!

      patch '/admin/settings', params: { instance_settings: { geoapify_api_key: 'new-key' } }

      expect(InstanceSetting.find_by(key: 'geoapify_api_key')&.value).to eq('new-key')
    end

    # A hidden field cannot be disabled, so a pinned boolean posted on every
    # save and the page reported a refusal the operator could not act on.
    it 'does not emit a postable hidden field for a pinned boolean' do
      saved = ENV.fetch('STORE_GEODATA', nil)
      ENV['STORE_GEODATA'] = 'true'
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'points' }

      expect(response.body).not_to match(/name="instance_settings\[store_geodata\]"\s+value="false"/)
    ensure
      ENV['STORE_GEODATA'] = saved
      InstanceSettings::Resolver.reset!
    end
  end

  describe 'without any feature flag' do
    before { sign_in admin }

    it 'saves a setting while Flipper has never heard of instance settings' do
      patch '/admin/settings', params: { instance_settings: { photon_api_host: 'stored.example.com' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('stored.example.com')
    end
  end

  describe 'settings navigation' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'puts Instance settings in the settings tabs for an admin, marked current' do
      sign_in admin

      get '/admin/settings'

      expect(response.body).to match(%r{<a(?=[^>]*href="/admin/settings")(?=[^>]*tab-active)[^>]*>})
    end

    it 'offers the Instance tab to an admin on other settings pages' do
      sign_in admin

      get '/settings/general'

      expect(response.body).to include('href="/admin/settings"')
    end

    it 'does not offer the Instance tab to anyone else' do
      sign_in non_admin

      get '/settings/general'

      expect(response.body).not_to include('href="/admin/settings"')
    end
  end

  describe 'POST test_geocoding' do
    it 'is refused for a non-admin and makes no lookup' do
      allow(Geocoding::Search).to receive(:with_config)
      sign_in non_admin

      post '/admin/settings/test_geocoding'

      expect(response).not_to have_http_status(:ok)
      expect(Geocoding::Search).not_to have_received(:with_config)
    end

    it 'says geocoding is not configured when no provider resolves' do
      sign_in admin

      post '/admin/settings/test_geocoding'

      expect(flash[:alert]).to eq(I18n.t('admin.settings.test_geocoding.not_configured'))
    end

    it 'reports the place the saved provider answered with' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!
      use_real_geocoding_lookups
      allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
      stub_request(:get, %r{stored\.example\.com/reverse}).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { type: 'FeatureCollection',
                features: [{ type: 'Feature', properties: { city: 'Leipzig', country: 'Germany' },
                             geometry: { type: 'Point', coordinates: [12.3712, 51.3402] } }] }.to_json
      )
      sign_in admin

      post '/admin/settings/test_geocoding'

      expect(flash[:notice]).to eq(I18n.t('admin.settings.test_geocoding.success', place: 'Leipzig, Germany'))
    end

    it 'names a network failure instead of leaking an internal error' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!
      allow(Geocoding::Search).to receive(:with_config).and_raise(SocketError, 'getaddrinfo failed')
      sign_in admin

      post '/admin/settings/test_geocoding'

      expect(flash[:alert]).to include('SocketError')
    end
  end

  describe 'POST test_map_matching' do
    it 'is refused for a non-admin without contacting Atlas' do
      allow(MapMatching::Atlas::ConnectionTest).to receive(:call)
      sign_in non_admin

      post '/admin/settings/test_map_matching'

      expect(response).not_to have_http_status(:ok)
      expect(MapMatching::Atlas::ConnectionTest).not_to have_received(:call)
    end

    it 'returns the operator to map matching settings with the result' do
      allow(MapMatching::Atlas::ConnectionTest).to receive(:call).and_return([:notice, 'Atlas is ready'])
      sign_in admin

      post '/admin/settings/test_map_matching'

      expect(response).to redirect_to(admin_settings_path(section: 'map_matching'))
      expect(flash[:notice]).to eq('Atlas is ready')
    end
  end

  describe 'secrets and the provider in effect' do
    before { sign_in admin }

    it 'says a stored secret cannot be decrypted instead of showing it as unset' do
      setting = InstanceSetting.create!(key: 'geoapify_api_key', value: 'token')
      InstanceSetting.connection.execute(
        InstanceSetting.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE id = ?', 'not-valid-ciphertext', setting.id]
        )
      )
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'geoapify' }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t('admin.settings.show.unreadable_secret')))
    end

    it 'replaces an undecryptable secret with the value the operator re-enters' do
      setting = InstanceSetting.create!(key: 'geoapify_api_key', value: 'token')
      InstanceSetting.connection.execute(
        InstanceSetting.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE id = ?', 'not-valid-ciphertext', setting.id]
        )
      )
      InstanceSettings::Resolver.reset!

      patch '/admin/settings', params: { instance_settings: { geoapify_api_key: 'fresh-key' } }

      expect(response).to have_http_status(:see_other)
      expect(InstanceSetting.find_by(key: 'geoapify_api_key').value).to eq('fresh-key')
    end

    it 'names the provider in effect and the variable pinning it, so a stored one it overrides is not a mystery' do
      saved = ENV.fetch('GEOAPIFY_API_KEY', nil)
      ENV['GEOAPIFY_API_KEY'] = 'env-geo-key'
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      status = response.body[%r{<div[^>]*data-testid="instance-settings-geocoding-status".*?</form>}m]
      expect(status).to include('Geoapify')
      expect(status).to include(I18n.t('admin.settings.show.pinned_hint', variable: 'GEOAPIFY_API_KEY'))
      expect(response.body).to match(
        /<a(?=[^>]*data-testid="instance-settings-section-geoapify")(?=[^>]*data-status="in_use")[^>]*>/
      )
    ensure
      ENV['GEOAPIFY_API_KEY'] = saved
      InstanceSettings::Resolver.reset!
    end

    it 'says geocoding is off when no provider is configured' do
      get '/admin/settings'

      expect(response.body).to include(ERB::Util.html_escape(I18n.t('admin.settings.show.geocoding.none')))
      expect(response.body).not_to include('/admin/settings/test_geocoding')
    end

    it 'shows HTTPS as on and locked for a Photon host that only answers over TLS' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'photon.komoot.io')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      toggle = response.body[/<input[^>]*id="instance_settings_photon_api_use_https"[^>]*>/m]
      expect(toggle).to include('checked')
      expect(toggle).to include('disabled')
      expect(response.body).not_to match(/name="instance_settings\[photon_api_use_https\]"\s+value="false"/)
    end

    it 'renders a whole-number rate without a decimal part' do
      InstanceSetting.create!(key: 'reverse_geocoding_rps', value: 5.0)
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'rate_limit' }

      expect(response.body[/<input[^>]*id="instance_settings_reverse_geocoding_rps"[^>]*>/m]).to include('value="5"')
    end

    it 'masks a pinned secret instead of calling it stored here' do
      saved = ENV.fetch('GEOAPIFY_API_KEY', nil)
      ENV['GEOAPIFY_API_KEY'] = 'env-geo-key'
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      field = response.body[/<input[^>]*id="instance_settings_geoapify_api_key"[^>]*>/m]
      expect(field).to include('placeholder="••••••••"')
      expect(field).not_to include('env-geo-key')
    ensure
      ENV['GEOAPIFY_API_KEY'] = saved
      InstanceSettings::Resolver.reset!
    end

    it 'offers to clear a secret that can no longer be decrypted' do
      setting = InstanceSetting.create!(key: 'locationiq_api_key', value: 'token')
      InstanceSetting.connection.execute(
        "UPDATE instance_settings SET encrypted_value = 'not-valid-ciphertext' WHERE id = #{setting.id}"
      )
      InstanceSettings::Resolver.reset!

      get '/admin/settings', params: { section: 'locationiq' }

      expect(response.body).to include('instance_settings_clear[locationiq_api_key]')
    end

    it 'does not claim an unreadable secret when every stored secret decrypts' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'token')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t('admin.settings.show.unreadable_secret')))
    end
  end

  describe 'locale parity' do
    it 'defines the admin settings strings in every shipped locale' do
      en = I18n.t('admin.settings.show.title', locale: :en, default: nil)
      expect(en).to be_present

      keys = %w[admin.settings.show.title settings.navigation.instance
                admin.settings.show.unreadable_secret admin.settings.test_geocoding.success
                admin.settings.show.geocoding.none admin.settings.show.geocoding.chain_hint
                admin.settings.show.providers.photon admin.settings.show.fields.store_geodata_hint
                admin.settings.show.geocoding.legacy_user_settings admin.settings.update.host_invalid
                admin.settings.update.chibigeo_key_required]
      %i[de es fr pl ca].product(keys).each do |locale, key|
        expect(I18n.t(key, locale: locale, default: nil)).to be_present, "missing #{key} for #{locale}"
      end
    end
  end
end
