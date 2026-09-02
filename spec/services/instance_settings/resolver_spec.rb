# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::Resolver do
  before { described_class.reset! }

  after { described_class.reset! }

  def with_env(name, value)
    original = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = original
  end

  describe 'precedence' do
    it 'prefers the environment over a stored value' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')

      with_env('PHOTON_API_HOST', 'env.example.com') do
        described_class.reset!
        resolved = described_class.get(:photon_api_host)

        expect(resolved.value).to eq('env.example.com')
        expect(resolved.source).to eq(:env)
        expect(resolved).to be_pinned
      end
    end

    it 'falls back to the stored value when the environment is silent' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')

      with_env('PHOTON_API_HOST', nil) do
        described_class.reset!
        resolved = described_class.get(:photon_api_host)

        expect(resolved.value).to eq('stored.example.com')
        expect(resolved.source).to eq(:stored)
        expect(resolved).not_to be_pinned
      end
    end

    it 'falls back to the registry default when neither supplies a value' do
      with_env('STORE_GEODATA', nil) do
        described_class.reset!
        resolved = described_class.get(:store_geodata)

        expect(resolved.value).to be(true)
        expect(resolved.source).to eq(:default)
      end
    end
  end

  describe 'blank environment variables' do
    # A compose file with an unresolved substitution produces FOO= . Reading that
    # as a pin would freeze the admin panel read-only on a value nobody chose.
    it 'treats a blank variable as unset rather than as a pin' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')

      with_env('PHOTON_API_HOST', '') do
        described_class.reset!
        resolved = described_class.get(:photon_api_host)

        expect(resolved.source).to eq(:stored)
        expect(resolved.value).to eq('stored.example.com')
      end
    end
  end

  describe 'stored false' do
    it 'reports a stored false as stored, not as an unset default' do
      InstanceSetting.create!(key: 'store_geodata', value: false)

      with_env('STORE_GEODATA', nil) do
        described_class.reset!
        resolved = described_class.get(:store_geodata)

        expect(resolved.value).to be(false)
        expect(resolved.source).to eq(:stored)
      end
    end
  end

  describe 'secrets' do
    # pluck bypasses the model, so an encrypted attribute can come back as
    # ciphertext unless the read path decrypts it.
    it 'resolves a stored secret as plaintext, not ciphertext' do
      InstanceSetting.create!(key: 'geoapify_api_key', value: 'plain-text-key')

      with_env('GEOAPIFY_API_KEY', nil) do
        described_class.reset!
        resolved = described_class.get(:geoapify_api_key)

        expect(resolved.value).to eq('plain-text-key')
        expect(resolved.source).to eq(:stored)
      end
    end
  end

  describe 'query behaviour' do
    it 'reads the whole table once rather than querying per key' do
      InstanceSetting.create!(key: 'photon_api_host', value: 'stored.example.com')
      described_class.reset!

      queries = 0
      counter = ->(_n, _s, _f, _i, payload) { queries += 1 if payload[:sql]&.include?('instance_settings') }

      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        described_class.get(:photon_api_host)
        described_class.get(:store_geodata)
        described_class.get(:geoapify_api_key)
      end

      expect(queries).to eq(1)
    end
  end

  describe 'boot safety' do
    # config/initializers/geocoder.rb resolves at boot, and the Docker image
    # build runs assets:precompile with no database at all.
    #
    # These stub InstanceSetting.all — the method load_stored actually calls.
    # They previously stubbed .pluck, which the implementation stopped using,
    # so all three passed against a healthy database and proved nothing.
    def stub_db_failure(error)
      relation = InstanceSetting.all
      allow(InstanceSetting).to receive(:all).and_return(relation)
      allow(relation).to receive(:each_with_object).and_raise(error)
    end

    it 'resolves from ENV when the table does not exist' do
      stub_db_failure(ActiveRecord::StatementInvalid.new('relation "instance_settings" does not exist'))

      with_env('PHOTON_API_HOST', 'env.example.com') do
        described_class.reset!

        expect { described_class.get(:photon_api_host) }.not_to raise_error
        expect(described_class.get(:photon_api_host).source).to eq(:env)
      end
    end

    it 'resolves from defaults when the table does not exist and ENV is silent' do
      stub_db_failure(ActiveRecord::StatementInvalid.new('relation "instance_settings" does not exist'))

      with_env('STORE_GEODATA', nil) do
        described_class.reset!

        expect(described_class.get(:store_geodata).value).to be(true)
        expect(described_class.get(:store_geodata).source).to eq(:default)
      end
    end

    it 'resolves from defaults when the database does not exist' do
      stub_db_failure(ActiveRecord::NoDatabaseError.new('no database'))

      with_env('STORE_GEODATA', nil) do
        described_class.reset!

        expect(described_class.get(:store_geodata).source).to eq(:default)
      end
    end

    it 'does not raise when the connection is not established' do
      stub_db_failure(ActiveRecord::ConnectionNotEstablished.new('down'))
      described_class.reset!

      expect { described_class.get(:photon_api_host) }.not_to raise_error
    end

    it 'does not raise when the postgres connection is bad' do
      stub_db_failure(PG::ConnectionBad.new('could not connect'))
      described_class.reset!

      expect { described_class.get(:photon_api_host) }.not_to raise_error
    end
  end

  describe '.value and .pinned?' do
    it 'exposes the bare value and the pinned predicate' do
      with_env('STORE_GEODATA', 'false') do
        described_class.reset!

        expect(described_class.value(:store_geodata)).to be(false)
        expect(described_class.pinned?(:store_geodata)).to be(true)
      end
    end
  end

  describe '.set' do
    it 'persists a value and makes it visible without an explicit reset' do
      with_env('PHOTON_API_HOST', nil) do
        described_class.reset!
        described_class.get(:photon_api_host)

        described_class.set(:photon_api_host, 'written.example.com')

        expect(described_class.get(:photon_api_host).value).to eq('written.example.com')
        expect(described_class.get(:photon_api_host).source).to eq(:stored)
      end
    end

    it 'refuses to write a key the environment pins' do
      with_env('PHOTON_API_HOST', 'env.example.com') do
        described_class.reset!

        expect { described_class.set(:photon_api_host, 'attempt.example.com') }
          .to raise_error(InstanceSettings::Resolver::PinnedSettingError, /PHOTON_API_HOST/)

        expect(InstanceSetting.find_by(key: 'photon_api_host')).to be_nil
      end
    end
  end
end
