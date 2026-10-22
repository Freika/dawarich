# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSetting do
  describe 'key validation' do
    it 'accepts a key the registry declares' do
      expect(described_class.new(key: 'store_geodata', value: true)).to be_valid
    end

    it 'rejects a key the registry does not declare' do
      setting = described_class.new(key: 'not_a_real_setting', value: 1)

      expect(setting).not_to be_valid
      expect(setting.errors[:key]).to be_present
    end

    it 'refuses a second row for the same key at the validation layer' do
      described_class.create!(key: 'photon_api_host', value: 'a.example.com')

      expect { described_class.create!(key: 'photon_api_host', value: 'b.example.com') }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    # The validation races under concurrency; the index is what actually holds.
    it 'refuses a second row for the same key at the database layer' do
      described_class.create!(key: 'photon_api_host', value: 'a.example.com')

      expect do
        described_class.connection.execute(
          'INSERT INTO instance_settings (key, value, created_at, updated_at) ' \
          "VALUES ('photon_api_host', '\"b.example.com\"', NOW(), NOW())"
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'secret storage' do
    it 'round-trips a secret without writing the plaintext to the database' do
      described_class.create!(key: 'photon_api_key', value: 'super-secret-token')

      expect(described_class.find_by(key: 'photon_api_key').value).to eq('super-secret-token')

      raw = described_class.connection.select_value(
        "SELECT encrypted_value FROM instance_settings WHERE key = 'photon_api_key'"
      )
      expect(raw).to be_present
      expect(raw).not_to include('super-secret-token')
    end

    it 'leaves the plain value column empty for a secret key' do
      described_class.create!(key: 'geoapify_api_key', value: 'abc123')

      raw = described_class.connection.select_value(
        "SELECT value FROM instance_settings WHERE key = 'geoapify_api_key'"
      )
      expect(raw).to be_nil
    end
  end

  describe 'non-secret storage' do
    it 'stores a boolean in the plain column and reads it back typed' do
      described_class.create!(key: 'store_geodata', value: false)

      expect(described_class.find_by(key: 'store_geodata').value).to be(false)
    end
  end

  describe '#readable_value?' do
    it 'is true for a decryptable secret' do
      setting = described_class.create!(key: 'photon_api_key', value: 'token')

      expect(setting.readable_value?).to be(true)
    end

    # Corrupts the stored ciphertext for real rather than stubbing the method
    # under test, which would only assert that a rescue rescues.
    it 'degrades to false instead of raising when the stored ciphertext is not decryptable' do
      setting = described_class.create!(key: 'photon_api_key', value: 'token')
      described_class.connection.execute(
        described_class.sanitize_sql_array(
          ['UPDATE instance_settings SET encrypted_value = ? WHERE id = ?', 'not-valid-ciphertext', setting.id]
        )
      )

      reloaded = described_class.find(setting.id)

      expect { reloaded.readable_value? }.not_to raise_error
      expect(reloaded.readable_value?).to be(false)
    end
  end
end
