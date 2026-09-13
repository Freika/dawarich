# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Settings' do
  let(:admin) { create(:user, admin: true) }
  let(:non_admin) { create(:user) }

  around do |example|
    saved = ENV.fetch('PHOTON_API_HOST', nil)
    ENV['PHOTON_API_HOST'] = nil
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = saved
    InstanceSettings::Resolver.reset!
  end

  before { allow(InstanceSettings).to receive(:enabled?).and_return(true) }

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
  end

  describe 'GET show' do
    before { sign_in admin }

    it 'renders a pinned setting as disabled and names the variable pinning it' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).to include('PHOTON_API_HOST')
      expect(response.body).to match(/photon_api_host[^>]*disabled/m)
    end

    # Differential: proves the assertion above is about pinning, not about every
    # field happening to carry the attribute.
    it 'leaves an unpinned field editable on the same page' do
      ENV['PHOTON_API_HOST'] = 'pinned.example.com'
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).to match(/photon_api_host[^>]*disabled/m)
      expect(response.body).not_to match(/nominatim_api_host[^>]*disabled/m)
    end

    it 'never renders a stored secret into the page' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'super-secret-value')
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

      expect(response.body).not_to include('super-secret-value')
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

      get '/admin/settings'

      expect(response.body).not_to match(/name="instance_settings\[store_geodata\]"\s+value="false"/)
    ensure
      ENV['STORE_GEODATA'] = saved
      InstanceSettings::Resolver.reset!
    end
  end

  describe 'while the resolver flag is off' do
    before do
      allow(InstanceSettings).to receive(:enabled?).and_return(false)
      sign_in admin
    end

    it 'refuses a write that nothing would read' do
      patch '/admin/settings', params: { instance_settings: { photon_api_host: 'stored.example.com' } }

      expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
      expect(flash[:alert]).to eq(I18n.t('admin.settings.update.disabled'))
    end

    it 'names the flag that turns the page on and disables the form' do
      get '/admin/settings'

      expect(response.body).to include(InstanceSettings::FLAG.to_s)
      expect(response.body).to match(/<fieldset[^>]*disabled/)
    end
  end

  describe 'with the resolver flag on' do
    before { sign_in admin }

    it 'does not disable the form' do
      get '/admin/settings'

      expect(response.body).not_to match(/<fieldset[^>]*disabled/)
      expect(response.body).not_to include(InstanceSettings::FLAG.to_s)
    end

    it 'says a stored secret cannot be decrypted instead of showing it as unset' do
      setting = InstanceSetting.create!(key: 'geoapify_api_key', value: 'token')
      InstanceSetting.connection.execute(
        InstanceSetting.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE id = ?', 'not-valid-ciphertext', setting.id]
        )
      )
      InstanceSettings::Resolver.reset!

      get '/admin/settings'

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

      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t('admin.settings.show.geocoding_pinned', provider: 'Geoapify',
                                                                            variable: 'GEOAPIFY_API_KEY'))
      )
    ensure
      ENV['GEOAPIFY_API_KEY'] = saved
      InstanceSettings::Resolver.reset!
    end

    it 'says geocoding is off when no provider is configured' do
      get '/admin/settings'

      expect(response.body).to include(ERB::Util.html_escape(I18n.t('admin.settings.show.geocoding_none')))
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

      keys = %w[admin.settings.show.title admin.settings.show.disabled_notice
                admin.settings.show.unreadable_secret admin.settings.update.disabled
                admin.settings.show.geocoding_pinned admin.settings.show.geocoding_stored
                admin.settings.show.geocoding_none]
      %i[de es fr pl ca].product(keys).each do |locale, key|
        expect(I18n.t(key, locale: locale, default: nil)).to be_present, "missing #{key} for #{locale}"
      end
    end
  end
end
