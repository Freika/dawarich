# frozen_string_literal: true

require 'rails_helper'
require_relative 'geocoding_fixture_determinism'

RSpec.describe GeocodingFixtureDeterminism do
  def capture_persisted_inputs(scope: nil)
    captured = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      described_class.with(scope:) do
        user = create(:user, email: 'fixture-determinism@example.test')
        point = create(:point, user:)
        place = user.places.create!(name: 'Fixture place', latitude: 51.3397, longitude: 12.3731)
        setting = InstanceSetting.create!(key: 'photon_api_key', value: 'fixture-determinism-key')
        ciphertext = setting.read_attribute_before_type_cast(:encrypted_value)
        wrong = ActiveRecord::Encryption::Encryptor.new.encrypt(
          'fixture-determinism-key',
          key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new('fixture-wrong-key')
        )
        expect(setting.reload.encrypted_value).to eq('fixture-determinism-key')
        expect { ActiveRecord::Encryption::Encryptor.new.decrypt(wrong) }
          .to raise_error(ActiveRecord::Encryption::Errors::Decryption)
        captured = { ids: [user.id, point.id, place.id, setting.id],
                     ciphertext_sha: Digest::SHA256.hexdigest(ciphertext),
                     wrong_ciphertext_sha: Digest::SHA256.hexdigest(wrong) }
      end
      raise ActiveRecord::Rollback
    end
    captured
  end

  it 'repeats real persisted identities and both real encryption key-provider outputs' do
    expect(capture_persisted_inputs).to eq(capture_persisted_inputs)
  end

  it 'separates fixture identities while preserving concrete consumer ranges' do
    locked = capture_persisted_inputs(scope: :place_name_locked)
    too_long = capture_persisted_inputs(scope: :place_name_too_long)
    expect(locked[:ids].zip(too_long[:ids]).all? { |left, right| left != right }).to be(true)

    described_class.with(scope: :point_batch) do |allocate_id|
      expect(Array.new(5) { allocate_id.call(Point) }).to eq([6207, 6208, 6209, 6210, 6211])
      expect { allocate_id.call(Point) }.to raise_error('geocoding fixture ID range exhausted in points')
    end
    described_class.with(scope: :country_alias_and_mismatch) do |allocate_id|
      expect(allocate_id.call(Country)).to eq(35)
      expect { allocate_id.call(Country) }.to raise_error('geocoding fixture ID range exhausted in countries')
    end
    expect { described_class.with(scope: :unknown_fixture) {} }.to raise_error(KeyError)
  end

  it 'fails closed on an existing fixture identity' do
    create(:user, id: described_class::FIRST_ID, email: 'existing-fixture-id@example.test')

    expect { described_class.with { create(:user, email: 'fixture-collision@example.test') } }
      .to raise_error('geocoding fixture ID collision in users')
  end

  it 'restores the original cipher and model callbacks when the fixture raises' do
    cipher = ActiveRecord::Encryption.cipher
    models = [User, Point, Place, Country, InstanceSetting]
    callbacks = models.index_with { |model| model._validation_callbacks.map(&:filter) }

    expect { described_class.with { raise 'fixture interrupted' } }.to raise_error('fixture interrupted')

    expect(ActiveRecord::Encryption.cipher).to equal(cipher)
    encryptor = ActiveRecord::Encryption::Encryptor.new
    expect(Digest::SHA256.hexdigest(encryptor.encrypt('fixture-outside-scope')))
      .not_to eq(Digest::SHA256.hexdigest(encryptor.encrypt('fixture-outside-scope')))
    expect(models.index_with { |model| model._validation_callbacks.map(&:filter) }).to eq(callbacks)
  end
end
