# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geocoding::BackfillInstanceSettings do
  around do |example|
    saved = ENV.fetch('PHOTON_API_HOST', nil)
    ENV['PHOTON_API_HOST'] = nil
    InstanceSettings::Resolver.reset!
    example.run
  ensure
    ENV['PHOTON_API_HOST'] = saved
    InstanceSettings::Resolver.reset!
  end

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

  it 'leaves an existing instance setting alone rather than overwriting it' do
    InstanceSetting.create!(key: 'photon_api_host', value: 'already.example.com')
    geocoding_setting(create(:user), host: 'other.example.com')

    described_class.call

    expect(InstanceSetting.find_by(key: 'photon_api_host').value).to eq('already.example.com')
  end
end
