# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::SendTest do
  let(:user) { create(:user) }
  let!(:place) { create(:place, :geofence, user:) }
  let(:webhook) { create(:webhook, user:) }

  it 'delivers a synthetic enter to that webhook only, leaving state and the log alone' do
    create(:webhook, user:)
    GeofenceEvents::StateStore.new(user).reset!

    expect { described_class.call(webhook) }.to have_enqueued_job(Webhooks::DeliverJob).exactly(:once)
    expect(WebhookDelivery.sole.webhook).to eq(webhook)
    expect(GeofenceEvent.real).to be_empty
    expect(GeofenceEvents::StateStore.new(user).inside_ids).to be_empty
  end

  it 'uses the first place the webhook listens to' do
    other = create(:place, :geofence, user:)
    webhook.update!(place_ids: [other.id])

    described_class.call(webhook)

    expect(GeofenceEvent.sole.place).to eq(other)
  end

  it 'returns nil when the user has no places' do
    place.destroy!

    expect(described_class.call(webhook)).to be_nil
  end

  describe 'archived geofences', :archive do
    it 'does not send a test to an archived subscribed Place' do
      place.update!(archived: true)
      webhook.update!(place_ids: [place.id])

      expect { expect(described_class.call(webhook)).to be_nil }.not_to change(GeofenceEvent, :count)
    end

    it 'sends to an active Place when the first geofence is archived' do
      place.update!(archived: true)
      active = create(:place, :geofence, user:)

      described_class.call(webhook)

      expect(GeofenceEvent.sole.place).to eq(active)
    end
  end

  it 'snapshots the place name for a synthetic event', :place_retention do
    described_class.call(webhook)

    expect(GeofenceEvent.sole.place_name).to eq(place.name)
  end
end
