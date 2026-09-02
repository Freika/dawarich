# frozen_string_literal: true

require 'rails_helper'

# Regressions for defects found during verification review. Each one shipped
# green before it was caught, so each gets an explicit test.
RSpec.describe 'Instance settings review regressions' do
  before { InstanceSettings::Resolver.reset! }

  after { InstanceSettings::Resolver.reset! }

  describe 'the flag is not read from the database on every call' do
    # Point evaluates DawarichSettings.store_geodata? once per created row, and
    # Flipper's memoizer is Rack middleware so it does not cover Sidekiq.
    it 'reads Flipper once for many predicate calls' do
      allow(Flipper).to receive(:enabled?).with(InstanceSettings::FLAG).and_return(false)
      InstanceSettings.reset_flag_cache!

      10.times { InstanceSettings.enabled? }

      expect(Flipper).to have_received(:enabled?).once
    end

    it 'still degrades to disabled when Flipper raises' do
      allow(Flipper).to receive(:enabled?).and_raise(StandardError, 'flipper down')
      InstanceSettings.reset_flag_cache!

      expect(InstanceSettings.enabled?).to be(false)
    end
  end

  describe 'an unreadable secret' do
    it 'falls through to the registry default instead of reporting a stored nil' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'readable')
      # Corrupt the real ciphertext rather than stubbing the accessor the code
      # under test calls, which would only assert that a rescue rescues.
      InstanceSetting.connection.execute(
        InstanceSetting.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE key = ?',
           'not-valid-ciphertext', 'geoapify_api_key']
        )
      )
      InstanceSettings::Resolver.reset!

      resolved = InstanceSettings::Resolver.get(:geoapify_api_key)

      expect(resolved.source).to eq(:default)
      expect(resolved.value).to be_nil
    end

    # The previous version of this example created only a readable row, so it
    # asserted nothing about isolation. One row must actually be undecryptable
    # alongside a good one, or it passes against a whole-load rescue too.
    it 'does not blank the other settings on the instance' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'unreadable-soon')
      InstanceSetting.create!(key: 'photon_api_host', value: 'survives.example.com')
      InstanceSetting.connection.execute(
        InstanceSetting.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE key = ?',
           'not-valid-ciphertext', 'geoapify_api_key']
        )
      )
      InstanceSettings::Resolver.reset!

      expect(InstanceSettings::Resolver.get(:geoapify_api_key).source).to eq(:default)
      expect(InstanceSettings::Resolver.get(:photon_api_host).value).to eq('survives.example.com')
    end
  end

  describe 'unreadable encryption configuration' do
    # Neither reviewer filed this; found while checking their notes. If the
    # encryption keys are missing or malformed, reading a secret raises
    # Errors::Configuration, which was in neither rescue list — so every
    # resolver read died, including the admin page that would fix it.
    it 'degrades to the default rather than taking down every read' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'a-key')
      InstanceSetting.create!(key: 'photon_api_host', value: 'survives.example.com')
      allow_any_instance_of(InstanceSetting).to receive(:value)
        .and_raise(ActiveRecord::Encryption::Errors::Configuration, 'no keys')
      InstanceSettings::Resolver.reset!

      expect { InstanceSettings::Resolver.get(:geoapify_api_key) }.not_to raise_error
      expect(InstanceSettings::Resolver.get(:geoapify_api_key).source).to eq(:default)
      expect(InstanceSettings::Resolver.get(:photon_api_host).value).to eq('survives.example.com')
    end
  end

  describe 'a row that exists but carries no value' do
    # The secret-wipe defect left rows with a NULL value. `stored.key?` was true
    # for them, so the resolver reported source :stored with a nil value and
    # geocoding died silently instead of falling back to the default.
    it 'falls back to the default rather than reporting a stored nil' do
      InstanceSetting.connection.execute(
        'INSERT INTO instance_settings (key, value, encrypted_value, created_at, updated_at) ' \
        "VALUES ('photon_api_host', NULL, NULL, NOW(), NOW())"
      )
      InstanceSettings::Resolver.reset!

      resolved = InstanceSettings::Resolver.get(:photon_api_host)

      expect(resolved.source).to eq(:default)
    end

    it 'does the same for a secret key' do
      InstanceSetting.connection.execute(
        'INSERT INTO instance_settings (key, value, encrypted_value, created_at, updated_at) ' \
        "VALUES ('geoapify_api_key', NULL, NULL, NOW(), NOW())"
      )
      InstanceSettings::Resolver.reset!

      resolved = InstanceSettings::Resolver.get(:geoapify_api_key)

      expect(resolved.source).to eq(:default)
      expect(resolved.value).to be_nil
    end
  end

  describe 'the snapshot' do
    # Storing data and timestamp separately let a concurrent reset! land between
    # them, leaving a snapshot the TTL could never expire.
    it 'expires even when reset! runs while a load is in flight' do
      InstanceSettings::Resolver.get(:photon_api_host)
      InstanceSettings::Resolver.reset!
      InstanceSetting.create!(key: 'photon_api_host', value: 'later.example.com')

      expect(InstanceSettings::Resolver.get(:photon_api_host).value).to eq('later.example.com')
    end
  end
end
