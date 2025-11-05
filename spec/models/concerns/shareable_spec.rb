# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shareable do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip, user: user, name: 'Test Trip',
                  started_at: 1.week.ago, ended_at: Time.current)
  end

  describe '#generate_sharing_uuid' do
    it 'generates a UUID before create' do
      new_trip = build(:trip, user: user)
      expect(new_trip.sharing_uuid).to be_nil
      new_trip.save!
      expect(new_trip.sharing_uuid).to be_present
      expect(new_trip.sharing_uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end
  end

  describe '#sharing_enabled?' do
    it 'returns false by default' do
      expect(trip.sharing_enabled?).to be false
    end

    it 'returns true when enabled' do
      trip.update!(sharing_settings: { 'enabled' => true })
      expect(trip.sharing_enabled?).to be true
    end

    it 'returns false when disabled' do
      trip.update!(sharing_settings: { 'enabled' => false })
      expect(trip.sharing_enabled?).to be false
    end
  end

  describe '#sharing_expired?' do
    it 'returns false when no expiration is set' do
      expect(trip.sharing_expired?).to be false
    end

    it 'returns false when expires_at is in the future' do
      trip.update!(sharing_settings: {
                     'expiration' => '24h',
                     'expires_at' => 1.hour.from_now.iso8601
                   })
      expect(trip.sharing_expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      trip.update!(sharing_settings: {
                     'expiration' => '1h',
                     'expires_at' => 1.hour.ago.iso8601
                   })
      expect(trip.sharing_expired?).to be true
    end

    it 'returns true when expiration is set but expires_at is missing' do
      trip.update!(sharing_settings: {
                     'expiration' => '24h',
                     'expires_at' => nil
                   })
      expect(trip.sharing_expired?).to be true
    end
  end

  describe '#public_accessible?' do
    it 'returns false by default' do
      expect(trip.public_accessible?).to be false
    end

    it 'returns true when enabled and not expired' do
      trip.update!(sharing_settings: {
                     'enabled' => true,
                     'expiration' => '24h',
                     'expires_at' => 1.hour.from_now.iso8601
                   })
      expect(trip.public_accessible?).to be true
    end

    it 'returns false when enabled but expired' do
      trip.update!(sharing_settings: {
                     'enabled' => true,
                     'expiration' => '1h',
                     'expires_at' => 1.hour.ago.iso8601
                   })
      expect(trip.public_accessible?).to be false
    end

    it 'returns false when disabled' do
      trip.update!(sharing_settings: {
                     'enabled' => false,
                     'expiration' => '24h',
                     'expires_at' => 1.hour.from_now.iso8601
                   })
      expect(trip.public_accessible?).to be false
    end
  end

  describe '#enable_sharing!' do
    it 'enables sharing with default 24h expiration' do
      trip.enable_sharing!
      expect(trip.sharing_enabled?).to be true
      expect(trip.sharing_settings['expiration']).to eq('24h')
      expect(trip.sharing_settings['expires_at']).to be_present
    end

    it 'enables sharing with custom expiration' do
      trip.enable_sharing!(expiration: '1h')
      expect(trip.sharing_enabled?).to be true
      expect(trip.sharing_settings['expiration']).to eq('1h')
    end

    it 'enables sharing with permanent expiration' do
      trip.enable_sharing!(expiration: 'permanent')
      expect(trip.sharing_enabled?).to be true
      expect(trip.sharing_settings['expiration']).to eq('permanent')
      expect(trip.sharing_settings['expires_at']).to be_nil
    end

    it 'defaults to 24h for invalid expiration' do
      trip.enable_sharing!(expiration: 'invalid')
      expect(trip.sharing_settings['expiration']).to eq('24h')
    end

    it 'stores additional options like share_notes' do
      trip.enable_sharing!(expiration: '24h', share_notes: true)
      expect(trip.sharing_settings['share_notes']).to be true
    end

    it 'stores additional options like share_photos' do
      trip.enable_sharing!(expiration: '24h', share_photos: true)
      expect(trip.sharing_settings['share_photos']).to be true
    end

    it 'generates a sharing_uuid if not present' do
      trip.update_column(:sharing_uuid, nil)
      trip.enable_sharing!
      expect(trip.sharing_uuid).to be_present
    end

    it 'keeps existing sharing_uuid' do
      original_uuid = trip.sharing_uuid
      trip.enable_sharing!
      expect(trip.sharing_uuid).to eq(original_uuid)
    end
  end

  describe '#disable_sharing!' do
    before do
      trip.enable_sharing!(expiration: '24h')
    end

    it 'disables sharing' do
      trip.disable_sharing!
      expect(trip.sharing_enabled?).to be false
    end

    it 'clears expiration settings' do
      trip.disable_sharing!
      expect(trip.sharing_settings['expiration']).to be_nil
      expect(trip.sharing_settings['expires_at']).to be_nil
    end

    it 'keeps the sharing_uuid' do
      original_uuid = trip.sharing_uuid
      trip.disable_sharing!
      expect(trip.sharing_uuid).to eq(original_uuid)
    end
  end

  describe '#generate_new_sharing_uuid!' do
    it 'generates a new UUID' do
      original_uuid = trip.sharing_uuid
      trip.generate_new_sharing_uuid!
      expect(trip.sharing_uuid).not_to eq(original_uuid)
      expect(trip.sharing_uuid).to be_present
    end
  end

  describe '#share_notes?' do
    it 'returns false by default' do
      expect(trip.share_notes?).to be false
    end

    it 'returns true when share_notes is enabled' do
      trip.update!(sharing_settings: { 'share_notes' => true })
      expect(trip.share_notes?).to be true
    end

    it 'returns false when share_notes is disabled' do
      trip.update!(sharing_settings: { 'share_notes' => false })
      expect(trip.share_notes?).to be false
    end
  end

  describe '#share_photos?' do
    it 'returns false by default' do
      expect(trip.share_photos?).to be false
    end

    it 'returns true when share_photos is enabled' do
      trip.update!(sharing_settings: { 'share_photos' => true })
      expect(trip.share_photos?).to be true
    end

    it 'returns false when share_photos is disabled' do
      trip.update!(sharing_settings: { 'share_photos' => false })
      expect(trip.share_photos?).to be false
    end
  end
end
