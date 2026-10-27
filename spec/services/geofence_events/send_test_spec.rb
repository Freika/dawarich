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

  it 'snapshots the place name for a synthetic event', :place_retention do
    described_class.call(webhook)

    expect(GeofenceEvent.sole.place_name).to eq(place.name)
  end
end
