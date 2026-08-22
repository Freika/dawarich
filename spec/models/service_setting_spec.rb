# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceSetting do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it 'rejects an unknown provider for the geocoding service' do
      setting = build(:service_setting, provider: 'osm')

      expect(setting).not_to be_valid
      expect(setting.errors[:provider]).to be_present
    end

    it 'requires a host for photon' do
      setting = build(:service_setting, provider: 'photon', config: {})

      expect(setting).not_to be_valid
      expect(setting.errors[:base]).to be_present
    end

    it 'requires a host for nominatim' do
      setting = build(:service_setting, provider: 'nominatim', config: {})

      expect(setting).not_to be_valid
    end

    it 'requires an api key for geoapify' do
      setting = build(:service_setting, provider: 'geoapify', config: {})

      expect(setting).not_to be_valid
      expect(setting.errors[:base]).to be_present
    end

    it 'requires an api key for locationiq' do
      setting = build(:service_setting, provider: 'locationiq', config: {})

      expect(setting).not_to be_valid
    end

    it 'accepts geoapify with an api key and no host' do
      setting = build(:service_setting, provider: 'geoapify', config: {}, api_key: 'key-123')

      expect(setting).to be_valid
    end

    it 'rejects a host containing whitespace' do
      setting = build(:service_setting, provider: 'photon', config: { 'host' => 'photon example com' })

      expect(setting).not_to be_valid
    end

    it 'rejects a duplicate provider row for the same user and service' do
      existing = create(:service_setting)
      duplicate = build(:service_setting, user: existing.user, provider: existing.provider)

      expect(duplicate).not_to be_valid
    end
  end

  describe 'normalization' do
    it 'strips a pasted scheme and downcases the host' do
      setting = create(:service_setting, config: { 'host' => 'https://Photon.Example.COM' })

      expect(setting.host).to eq('photon.example.com')
    end

    it 'strips whitespace and trailing slashes from the host' do
      setting = create(:service_setting, config: { 'host' => '  photon.example.com/  ' })

      expect(setting.host).to eq('photon.example.com')
    end

    it 'keeps a port suffix' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com:8080' })

      expect(setting.host).to eq('photon.example.com:8080')
    end

    it 'accepts docker-style underscore hostnames' do
      expect(build(:service_setting, config: { 'host' => 'my_photon' })).to be_valid
    end

    it 'accepts reverse-proxy hosts with a path suffix' do
      expect(build(:service_setting, config: { 'host' => 'proxy.example.com/photon' })).to be_valid
    end

    it 'forces https for photon.komoot.io' do
      setting = create(:service_setting, config: { 'host' => 'photon.komoot.io', 'use_https' => false })

      expect(setting.use_https).to be(true)
    end

    it 'forces https for the ChibiGeo host despite its path suffix' do
      setting = create(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon', 'use_https' => false },
                                         api_key: 'ck_test')

      expect(setting.use_https).to be(true)
    end

    it 'forces https for photon.dawarich.app even with a port' do
      setting = create(:service_setting, config: { 'host' => 'photon.dawarich.app:443', 'use_https' => false })

      expect(setting.use_https).to be(true)
    end

    it 'respects an explicit use_https false for other hosts' do
      setting = create(:service_setting, config: { 'host' => 'photon.internal.lan', 'use_https' => false })

      expect(setting.use_https).to be(false)
    end

    it 'defaults use_https to true when unset' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com' })

      expect(setting.use_https).to be(true)
    end
  end

  describe 'ChibiGeo host requirements' do
    it 'requires an api key when the photon host is ChibiGeo' do
      setting = build(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon' })

      expect(setting).not_to be_valid
      expect(setting.errors.full_messages.join).to match(/API key/i)
    end

    it 'is valid with a ChibiGeo host and an api key' do
      setting = build(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon' }, api_key: 'ck_test')

      expect(setting).to be_valid
    end
  end

  describe 'error copy' do
    it 'names the problem in a full sentence' do
      setting = build(:service_setting, provider: 'photon', config: {})
      setting.valid?

      expect(setting.errors.full_messages.join).to match(/host/i)
      expect(setting.errors.full_messages.join).not_to match(/Config|Credentials/)
    end
  end

  describe 'credentials encryption' do
    it 'does not store the api key in plaintext' do
      setting = create(:service_setting, provider: 'geoapify', config: {}, api_key: 'super-secret-key')

      raw = ActiveRecord::Base.connection.select_value(
        "SELECT credentials FROM service_settings WHERE id = #{setting.id}"
      )

      expect(raw).to be_present
      expect(raw).not_to include('super-secret-key')
      expect(setting.reload.api_key).to eq('super-secret-key')
    end

    it 'round-trips api_key through the credentials JSON' do
      setting = build(:service_setting, provider: 'geoapify', config: {})
      setting.api_key = 'abc'

      expect(setting.api_key).to eq('abc')

      setting.api_key = nil

      expect(setting.api_key).to be_nil
      expect(setting.credentials).to be_nil
    end
  end

  describe '#readable_credentials?' do
    it 'is true for readable credentials and rows without credentials' do
      with_key = create(:service_setting, provider: 'geoapify', config: {}, api_key: 'k')
      without_key = create(:service_setting)

      expect(with_key.readable_credentials?).to be(true)
      expect(without_key.readable_credentials?).to be(true)
    end

    it 'is false when the ciphertext cannot be decrypted' do
      setting = create(:service_setting, provider: 'geoapify', config: {}, api_key: 'k')
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = 'garbage' WHERE id = #{setting.id}"
      )

      expect(described_class.find(setting.id).readable_credentials?).to be(false)
    end

    it 'reads api_key as nil instead of raising when the ciphertext cannot be decrypted' do
      setting = create(:service_setting, provider: 'geoapify', config: {}, api_key: 'k')
      ActiveRecord::Base.connection.execute(
        "UPDATE service_settings SET credentials = 'garbage' WHERE id = #{setting.id}"
      )

      expect(described_class.find(setting.id).api_key).to be_nil
    end
  end

  describe '#activate!' do
    it 'sets the row active and clears the previous active row for the same service' do
      user = create(:user)
      photon = create(:service_setting, user: user, provider: 'photon')
      geoapify = create(:service_setting, user: user, provider: 'geoapify', config: {}, api_key: 'k')

      photon.activate!
      geoapify.activate!

      expect(photon.reload.active).to be(false)
      expect(geoapify.reload.active).to be(true)
    end

    it 'is enforced by the database when bypassing activate!' do
      user = create(:user)
      create(:service_setting, user: user, provider: 'photon', active: true)
      other = create(:service_setting, user: user, provider: 'geoapify', config: {}, api_key: 'k')

      expect do
        ActiveRecord::Base.connection.execute(
          "UPDATE service_settings SET active = TRUE WHERE id = #{other.id}"
        )
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe 'geocoding predicates' do
    it 'reports komoot for the public komoot host' do
      setting = build(:service_setting, config: { 'host' => 'photon.komoot.io' })

      expect(setting.komoot?).to be(true)
    end

    it 'does not report komoot for other hosts or providers' do
      photon = build(:service_setting, config: { 'host' => 'photon.example.com' })
      geoapify = build(:service_setting, provider: 'geoapify', config: {}, api_key: 'k')

      expect(photon.komoot?).to be(false)
      expect(geoapify.komoot?).to be(false)
    end

    it 'reports paid for geoapify and locationiq only' do
      expect(build(:service_setting, provider: 'geoapify', config: {}, api_key: 'k').paid?).to be(true)
      expect(build(:service_setting, provider: 'locationiq', config: {}, api_key: 'k').paid?).to be(true)
      expect(build(:service_setting).paid?).to be(false)
    end
  end
  describe 'geocoding rps' do
    it 'reads the configured rate' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com', 'rps' => 4 })

      expect(setting.rps).to eq(4.0)
    end

    it 'is nil for a custom host with no rate set' do
      expect(create(:service_setting).rps).to be_nil
    end

    it 'pins komoot to one request per second whatever was submitted' do
      setting = create(:service_setting, config: { 'host' => 'photon.komoot.io', 'rps' => 50 })

      expect(setting.rps).to eq(1.0)
    end

    it 'pins komoot to one request per second when nothing was submitted' do
      setting = create(:service_setting, config: { 'host' => 'photon.komoot.io' })

      expect(setting.rps).to eq(1.0)
    end

    it 'raises a chibigeo rate below the free tier up to the free tier' do
      setting = create(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon', 'rps' => 0.2 },
                                         api_key: 'ck_test')

      expect(setting.rps).to eq(1.0)
    end

    it 'lowers a chibigeo rate above the top public plan down to it' do
      setting = create(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon', 'rps' => 100 },
                                         api_key: 'ck_test')

      expect(setting.rps).to eq(25.0)
    end

    it 'keeps a chibigeo rate that matches a real plan' do
      setting = create(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon', 'rps' => 5 },
                                         api_key: 'ck_test')

      expect(setting.rps).to eq(5.0)
    end

    it 'defaults chibigeo to the free tier when nothing was submitted' do
      setting = create(:service_setting, config: { 'host' => 'app.chibigeo.com/v1/photon' }, api_key: 'ck_test')

      expect(setting.rps).to eq(1.0)
    end

    it 'clamps an absurd custom rate into the sanity range' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com', 'rps' => 99_999 })

      expect(setting.rps).to eq(Geocoding::RateLimits::CUSTOM_MAX)
    end

    it 'reads a blank submitted rate as unlimited' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com', 'rps' => '' })

      expect(setting.rps).to be_nil
      expect(setting.config).not_to have_key('rps')
    end

    it 'survives a reload' do
      setting = create(:service_setting, config: { 'host' => 'photon.example.com', 'rps' => '2.5' })

      expect(setting.reload.rps).to eq(2.5)
    end

    it 'applies to providers other than photon' do
      setting = create(:service_setting, :geoapify, config: { 'rps' => '5' })

      expect(setting.rps).to eq(5.0)
    end
  end
end
