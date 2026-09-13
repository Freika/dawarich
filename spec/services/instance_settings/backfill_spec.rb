# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::Backfill do
  around do |example|
    saved = ENV.fetch('PHOTON_API_HOST', nil)
    ENV['PHOTON_API_HOST'] = nil
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = saved
    InstanceSettings::Resolver.reset!
  end

  before { ActiveRecord::Base.connection.execute('TRUNCATE users CASCADE') }

  def geocoding_setting(user, host:, provider: 'photon', api_key: nil)
    setting = user.service_settings.new(service: :geocoding, provider: provider,
                                        config: { 'host' => host, 'use_https' => true }, active: true)
    setting.api_key = api_key if api_key
    setting.save!
    setting
  end

  it 'carries a single active configuration across' do
    geocoding_setting(create(:user), host: 'only.example.com')

    described_class.call

    expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('only.example.com')
  end

  it 'carries an agreed configuration across once' do
    geocoding_setting(create(:user), host: 'same.example.com')
    geocoding_setting(create(:user), host: 'same.example.com')

    described_class.call

    expect(InstanceSetting.where(key: 'photon_api_host').count).to eq(1)
    expect(InstanceSetting.find_by(key: 'photon_api_host').value).to eq('same.example.com')
  end

  # Silently electing one user's provider for the whole instance is data loss
  # wearing a migration's clothes.
  it 'writes nothing when active configurations disagree, and says which they were' do
    geocoding_setting(create(:user), host: 'one.example.com')
    geocoding_setting(create(:user), host: 'two.example.com')

    expect(Rails.logger).to receive(:warn).with(/one\.example\.com/).at_least(:once)

    described_class.call

    expect(InstanceSetting.where(key: 'photon_api_host')).to be_empty
  end

  it "writes nothing when some users have no configuration, so one user's key never serves everyone" do
    geocoding_setting(create(:user), host: nil, provider: 'geoapify', api_key: 'personal-key')
    create(:user)

    described_class.call

    expect(InstanceSetting.count).to eq(0)
  end

  it 'does not count a soft-deleted user as lacking a configuration' do
    geocoding_setting(create(:user), host: 'only.example.com')
    create(:user).update_column(:deleted_at, Time.current)

    described_class.call

    expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('only.example.com')
  end

  it "ignores a soft-deleted user's configuration rather than letting it block agreement" do
    geocoding_setting(create(:user), host: 'live.example.com')
    deleted = create(:user)
    geocoding_setting(deleted, host: 'deleted.example.com')
    deleted.update_column(:deleted_at, Time.current)

    described_class.call

    expect(InstanceSetting.find_by(key: 'photon_api_host')&.value).to eq('live.example.com')
  end

  it "never promotes a soft-deleted user's configuration when no live user has one" do
    deleted = create(:user)
    geocoding_setting(deleted, host: nil, provider: 'geoapify', api_key: 'departed-key')
    deleted.update_column(:deleted_at, Time.current)

    described_class.call

    expect(InstanceSetting.count).to eq(0)
  end

  it 'does nothing and does not raise on an instance with no users' do
    expect { described_class.call }.not_to raise_error
    expect(InstanceSetting.count).to eq(0)
  end

  it 'never deletes or mutates the per-user rows it read' do
    setting = geocoding_setting(create(:user), host: 'kept.example.com')
    original = setting.attributes

    described_class.call

    expect(setting.reload.attributes).to eq(original)
  end

  it 'carries an api key across into the encrypted column' do
    geocoding_setting(create(:user), host: nil, provider: 'geoapify', api_key: 'carried-key')

    described_class.call

    expect(InstanceSetting.find_by(key: 'geoapify_api_key')&.value).to eq('carried-key')
    raw = InstanceSetting.connection.select_value(
      "SELECT encrypted_value FROM instance_settings WHERE key = 'geoapify_api_key'"
    )
    expect(raw).not_to include('carried-key')
  end

  describe 'from the environment' do
    def stored(key)
      InstanceSetting.find_by(key: key)&.value
    end

    it 'copies every variable that is set, typed as the registry declares' do
      ENV['PHOTON_API_HOST'] = 'photon.env.example.com'
      ENV['PHOTON_API_KEY'] = 'env-photon-key'
      ENV['PHOTON_API_USE_HTTPS'] = 'false'
      ENV['REVERSE_GEOCODING_RPS'] = '5'
      ENV['STORE_GEODATA'] = 'false'

      described_class.call

      expect(stored('photon_api_host')).to eq('photon.env.example.com')
      expect(stored('photon_api_key')).to eq('env-photon-key')
      expect(stored('photon_api_use_https')).to be(false)
      expect(stored('reverse_geocoding_rps')).to eq(5.0)
      expect(stored('store_geodata')).to be(false)
    end

    it 'keeps a copied secret out of the readable column' do
      ENV['GEOAPIFY_API_KEY'] = 'env-geo-key'

      described_class.call

      raw = InstanceSetting.connection.select_value(
        "SELECT CONCAT(value::text, encrypted_value) FROM instance_settings WHERE key = 'geoapify_api_key'"
      )
      expect(raw).not_to include('env-geo-key')
    end

    it 'skips a variable that is unset or blank' do
      ENV['NOMINATIM_API_HOST'] = '   '

      described_class.call

      expect(InstanceSetting.count).to eq(0)
    end

    it 'does not overwrite a value already stored' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'already.example.com')
      ENV['PHOTON_API_HOST'] = 'photon.env.example.com'

      described_class.call

      expect(stored('photon_api_host')).to eq('already.example.com')
    end

    it 'ignores per-user rows once the environment names a provider, so an old one cannot surface later' do
      ENV['GEOAPIFY_API_KEY'] = 'env-geo-key'
      geocoding_setting(create(:user), host: 'seeded-long-ago.example.com')

      described_class.call

      expect(stored('geoapify_api_key')).to eq('env-geo-key')
      expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
    end

    it 'still carries agreed per-user rows across when the environment names no provider' do
      ENV['STORE_GEODATA'] = 'true'
      geocoding_setting(create(:user), host: 'only.example.com')

      described_class.call

      expect(stored('store_geodata')).to be(true)
      expect(stored('photon_api_host')).to eq('only.example.com')
    end

    it 'never writes a copied value into the log' do
      messages = []
      allow(Rails.logger).to receive(:info) { |m| messages << m }
      allow(Rails.logger).to receive(:warn) { |m| messages << m }
      ENV['LOCATIONIQ_API_KEY'] = 'env-liq-secret'

      described_class.call

      expect(messages.join).not_to include('env-liq-secret')
    end
  end

  it 'leaves an existing instance setting alone rather than overwriting it' do
    InstanceSetting.create!(key: 'photon_api_host', value: 'already.example.com')
    geocoding_setting(create(:user), host: 'other.example.com')

    described_class.call

    expect(InstanceSetting.find_by(key: 'photon_api_host').value).to eq('already.example.com')
  end
end
