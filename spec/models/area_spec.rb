# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Area, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:visits).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:latitude) }
    it { is_expected.to validate_presence_of(:longitude) }
    it { is_expected.to validate_presence_of(:radius) }
    it { is_expected.to validate_numericality_of(:radius).is_greater_than(0) }

    it do
      is_expected.to validate_numericality_of(:latitude)
        .is_greater_than_or_equal_to(-90).is_less_than_or_equal_to(90)
    end

    it do
      is_expected.to validate_numericality_of(:longitude)
        .is_greater_than_or_equal_to(-180).is_less_than_or_equal_to(180)
    end
  end

  describe 'geofencing cleanup' do
    let(:user) { create(:user) }
    let(:area) { create(:area, user:) }

    it 'drops its events and its id from webhook filters when destroyed' do
      kept = create(:area, user:)
      webhook = create(:webhook, user:, area_ids: [area.id, kept.id])
      create(:webhook_delivery, webhook:, geofence_event: create(:geofence_event, user:, area:))

      area.destroy!

      expect(GeofenceEvent.where(area_id: area.id)).to be_empty
      expect(WebhookDelivery.count).to eq(0)
      expect(webhook.reload.area_ids).to eq([kept.id])
    end

    it 'loses its events through the database when deleted in bulk' do
      create(:geofence_event, user:, area:)

      user.areas.delete_all

      expect(GeofenceEvent.where(user_id: user.id)).to be_empty
    end
  end

  describe 'geofence state' do
    let(:user) { create(:user) }
    let(:store) { GeofenceEvents::StateStore.new(user) }
    let(:start) { 1_760_000_000 }

    before { store.reset! }

    def ingest(lon, minute)
      Points::Intake.call(user_id: user.id,
                          payloads: [{ lonlat: "POINT(#{lon} 52.52)", timestamp: start + (minute * 60), accuracy: 10 }])
    end

    it 'treats the user as already inside an area created around them' do
      ingest(13.4050, 0)
      create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100)

      ingest(13.4051, 1)

      expect(GeofenceEvent.where(user:)).to be_empty
    end

    it 'judges only the latest point, not older visits' do
      ingest(13.4050, 0)
      ingest(13.4300, 1)
      create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100)

      ingest(13.4051, 2)

      expect(GeofenceEvent.where(user:).pluck(:event_type)).to eq(%w[enter])
    end

    it 'treats the user as already outside an area moved away from them' do
      area = create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100)
      ingest(13.4050, 0)
      area.update!(longitude: 13.50)

      ingest(13.4051, 1)

      expect(GeofenceEvent.where(user:).pluck(:event_type)).to eq(%w[enter])
    end

    it 'forgets an area the user was inside when it is deleted' do
      area = create(:area, user:, latitude: 52.52, longitude: 13.405, radius: 100)
      ingest(13.4050, 0)

      area.destroy!

      expect(store.inside_ids).not_to include(area.id)
    end

    it 'saves the area even when the state store is unavailable' do
      allow(Sidekiq).to receive(:redis_pool).and_raise(RedisClient::CannotConnectError, 'down')

      expect { create(:area, user:) }.to change(Area, :count).by(1)
    end
  end

  describe 'factory' do
    it { expect(build(:area)).to be_valid }
  end
end
