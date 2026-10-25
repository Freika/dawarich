# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geofenceable do
  let(:user) { create(:user) }

  describe 'cleanup' do
    let(:place) { create(:place, :geofence, user:) }

    it 'drops its events and its id from webhook filters when destroyed' do
      kept = create(:place, :geofence, user:)
      webhook = create(:webhook, user:, place_ids: [place.id, kept.id])
      create(:webhook_delivery, webhook:, geofence_event: create(:geofence_event, user:, place:))

      place.destroy!

      expect(GeofenceEvent.where(place_id: place.id)).to be_empty
      expect(WebhookDelivery.count).to eq(0)
      expect(webhook.reload.place_ids).to eq([kept.id])
    end

    it 'switches off a webhook whose only place is deleted instead of widening it to every place' do
      webhook = create(:webhook, user:, place_ids: [place.id])

      place.destroy!

      expect(webhook.reload).to have_attributes(place_ids: [], active: false)
    end

    it 'loses its events and their deliveries through the database when deleted in bulk' do
      event = create(:geofence_event, user:, place:)
      create(:webhook_delivery, webhook: create(:webhook, user:), geofence_event: event)

      user.places.delete_all

      expect(GeofenceEvent.where(user_id: user.id)).to be_empty
      expect(WebhookDelivery.count).to eq(0)
    end

    it 'keeps its events but leaves webhook filters when notifications are switched off' do
      kept = create(:place, :geofence, user:)
      webhook = create(:webhook, user:, place_ids: [place.id, kept.id])
      create(:geofence_event, user:, place:)

      place.update!(geofence: false)

      expect(GeofenceEvent.where(place_id: place.id).count).to eq(1)
      expect(webhook.reload.place_ids).to eq([kept.id])
    end
  end

  describe 'state' do
    let(:store) { GeofenceEvents::StateStore.new(user) }
    let(:start) { 2.hours.ago.to_i }

    before { store.reset! }

    def ingest(lon, minute)
      Points::Intake.call(user_id: user.id,
                          payloads: [{ lonlat: "POINT(#{lon} 52.52)", timestamp: start + (minute * 60), accuracy: 10 }])
    end

    def home(**attributes)
      create(:place, user:, latitude: 52.52, longitude: 13.405, visit_radius: 100, **attributes)
    end

    it 'gives events only for the place that notifies when two places overlap' do
      home
      notifying = home(geofence: true)
      ingest(13.4300, 0)
      ingest(13.4050, 1)

      expect(GeofenceEvent.where(user:).pluck(:place_id, :event_type)).to eq([[notifying.id, 'enter']])
    end

    it 'treats the user as already inside a place created around them' do
      ingest(13.4050, 0)
      home(geofence: true)

      ingest(13.4051, 1)

      expect(GeofenceEvent.where(user:)).to be_empty
    end

    it 'treats the user as already inside when notifications are switched on where they are' do
      place = home
      ingest(13.4050, 0)
      place.update!(geofence: true)

      ingest(13.4051, 1)
      ingest(13.4300, 2)

      expect(GeofenceEvent.where(user:).pluck(:event_type)).to eq(%w[leave])
    end

    it 'judges only the latest point, not older visits' do
      ingest(13.4050, 0)
      ingest(13.4300, 1)
      home(geofence: true)

      ingest(13.4051, 2)

      expect(GeofenceEvent.where(user:).pluck(:event_type)).to eq(%w[enter])
    end

    it 'treats the user as already outside a place moved away from them' do
      place = home(geofence: true)
      ingest(13.4050, 0)
      place.update!(longitude: 13.50)

      ingest(13.4051, 1)

      expect(GeofenceEvent.where(user:).pluck(:event_type)).to eq(%w[enter])
    end

    it 'forgets a place the user was inside when it is deleted or stops notifying' do
      deleted = home(geofence: true)
      switched_off = home(geofence: true)
      ingest(13.4050, 0)

      deleted.destroy!
      switched_off.update!(geofence: false)

      expect(store.inside_ids).not_to include(deleted.id, switched_off.id)
    end

    it 'saves the place even when the state store is unavailable' do
      allow(Sidekiq).to receive(:redis_pool).and_raise(RedisClient::CannotConnectError, 'down')

      expect { home(geofence: true) }.to change(Place, :count).by(1)
    end
  end

  it 'counts as a confirmed place' do
    place = create(:place, :geofence, user:, source: :photon)

    expect(Place.confirmed_for(user)).to include(place)
  end
end
