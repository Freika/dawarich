# frozen_string_literal: true

RSpec.shared_examples 'shareable' do
  let(:user) { create(:user) }
  let(:shareable_model) { described_class.name.underscore.to_sym }
  let(:shareable) { create(shareable_model, user: user) }

  describe '#generate_sharing_uuid' do
    it 'generates a UUID before create' do
      new_record = build(shareable_model, user: user)
      expect(new_record.sharing_uuid).to be_nil
      new_record.save!
      expect(new_record.sharing_uuid).to be_present
      expect(new_record.sharing_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end
  end

  describe '#sharing_enabled?' do
    it 'returns false by default' do
      expect(shareable.sharing_enabled?).to be false
    end

    it 'returns true when enabled' do
      shareable.update!(sharing_settings: { 'enabled' => true })
      expect(shareable.sharing_enabled?).to be true
    end

    it 'returns false when disabled' do
      shareable.update!(sharing_settings: { 'enabled' => false })
      expect(shareable.sharing_enabled?).to be false
    end
  end

  describe '#sharing_expired?' do
    it 'returns false when no expiration is set' do
      expect(shareable.sharing_expired?).to be false
    end

    it 'returns false when expires_at is in the future' do
      shareable.update!(sharing_settings: {
                          'expiration' => '24h',
                          'expires_at' => 1.hour.from_now.iso8601
                        })
      expect(shareable.sharing_expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      shareable.update!(sharing_settings: {
                          'expiration' => '1h',
                          'expires_at' => 1.hour.ago.iso8601
                        })
      expect(shareable.sharing_expired?).to be true
    end

    it 'returns true when expiration is set but expires_at is missing' do
      shareable.update!(sharing_settings: {
                          'expiration' => '24h',
                          'expires_at' => nil
                        })
      expect(shareable.sharing_expired?).to be true
    end
  end

  describe '#public_accessible?' do
    it 'returns false by default' do
      expect(shareable.public_accessible?).to be false
    end

    it 'returns true when enabled and not expired' do
      shareable.update!(sharing_settings: {
                          'enabled' => true,
                          'expiration' => '24h',
                          'expires_at' => 1.hour.from_now.iso8601
                        })
      expect(shareable.public_accessible?).to be true
    end

    it 'returns false when enabled but expired' do
      shareable.update!(sharing_settings: {
                          'enabled' => true,
                          'expiration' => '1h',
                          'expires_at' => 1.hour.ago.iso8601
                        })
      expect(shareable.public_accessible?).to be false
    end

    it 'returns false when disabled' do
      shareable.update!(sharing_settings: {
                          'enabled' => false,
                          'expiration' => '24h',
                          'expires_at' => 1.hour.from_now.iso8601
                        })
      expect(shareable.public_accessible?).to be false
    end
  end

  describe '#enable_sharing!' do
    it 'enables sharing with default 24h expiration' do
      shareable.enable_sharing!
      expect(shareable.sharing_enabled?).to be true
      expect(shareable.sharing_settings['expiration']).to eq('24h')
      expect(shareable.sharing_settings['expires_at']).to be_present
    end

    it 'enables sharing with custom expiration' do
      shareable.enable_sharing!(expiration: '1h')
      expect(shareable.sharing_enabled?).to be true
      expect(shareable.sharing_settings['expiration']).to eq('1h')
    end

    it 'enables sharing with permanent expiration' do
      shareable.enable_sharing!(expiration: 'permanent')
      expect(shareable.sharing_enabled?).to be true
      expect(shareable.sharing_settings['expiration']).to eq('permanent')
      expect(shareable.sharing_settings['expires_at']).to be_nil
    end

    it 'defaults to 24h for invalid expiration' do
      shareable.enable_sharing!(expiration: 'invalid')
      expect(shareable.sharing_settings['expiration']).to eq('24h')
    end

    it 'generates a sharing_uuid if not present' do
      shareable.update_column(:sharing_uuid, nil)
      shareable.enable_sharing!
      expect(shareable.sharing_uuid).to be_present
    end

    it 'keeps existing sharing_uuid' do
      original_uuid = shareable.sharing_uuid
      shareable.enable_sharing!
      expect(shareable.sharing_uuid).to eq(original_uuid)
    end
  end

  describe '#disable_sharing!' do
    before do
      shareable.enable_sharing!(expiration: '24h')
    end

    it 'disables sharing' do
      shareable.disable_sharing!
      expect(shareable.sharing_enabled?).to be false
    end

    it 'clears expiration settings' do
      shareable.disable_sharing!
      expect(shareable.sharing_settings['expiration']).to be_nil
      expect(shareable.sharing_settings['expires_at']).to be_nil
    end

    it 'keeps the sharing_uuid' do
      original_uuid = shareable.sharing_uuid
      shareable.disable_sharing!
      expect(shareable.sharing_uuid).to eq(original_uuid)
    end
  end

  describe '#generate_new_sharing_uuid!' do
    it 'generates a new UUID' do
      original_uuid = shareable.sharing_uuid
      shareable.generate_new_sharing_uuid!
      expect(shareable.sharing_uuid).not_to eq(original_uuid)
      expect(shareable.sharing_uuid).to be_present
    end
  end

  describe '#share_notes?' do
    it 'returns false by default' do
      expect(shareable.share_notes?).to be false
    end

    it 'returns true when share_notes is enabled' do
      shareable.update!(sharing_settings: { 'share_notes' => true })
      expect(shareable.share_notes?).to be true
    end

    it 'returns false when share_notes is disabled' do
      shareable.update!(sharing_settings: { 'share_notes' => false })
      expect(shareable.share_notes?).to be false
    end
  end

  describe '#share_photos?' do
    it 'returns false by default' do
      expect(shareable.share_photos?).to be false
    end

    it 'returns true when share_photos is enabled' do
      shareable.update!(sharing_settings: { 'share_photos' => true })
      expect(shareable.share_photos?).to be true
    end

    it 'returns false when share_photos is disabled' do
      shareable.update!(sharing_settings: { 'share_photos' => false })
      expect(shareable.share_photos?).to be false
    end
  end
end
