# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::SendTest do
  let(:user) { create(:user) }
  let!(:area) { create(:area, user:) }
  let(:webhook) { create(:webhook, user:) }

  it 'delivers a synthetic enter to that webhook only, leaving state and the log alone' do
    create(:webhook, user:)
    GeofenceEvents::StateStore.new(user).reset!

    expect { described_class.call(webhook) }.to have_enqueued_job(Webhooks::DeliverJob).exactly(:once)
    expect(WebhookDelivery.sole.webhook).to eq(webhook)
    expect(GeofenceEvent.real).to be_empty
    expect(GeofenceEvents::StateStore.new(user).inside_ids).to be_empty
  end

  it 'uses the first area the webhook listens to' do
    other = create(:area, user:)
    webhook.update!(area_ids: [other.id])

    described_class.call(webhook)

    expect(GeofenceEvent.sole.area).to eq(other)
  end

  it 'returns nil when the user has no areas' do
    area.destroy!

    expect(described_class.call(webhook)).to be_nil
  end
end
