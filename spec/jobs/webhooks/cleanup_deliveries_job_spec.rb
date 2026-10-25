# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::CleanupDeliveriesJob do
  it 'deletes deliveries older than 30 days' do
    old = create(:webhook_delivery, created_at: 31.days.ago)
    recent = create(:webhook_delivery, webhook: old.webhook, created_at: 1.day.ago)

    described_class.perform_now

    expect(WebhookDelivery.all).to contain_exactly(recent)
  end

  it 'deletes old test events but keeps real ones' do
    old_test = create(:geofence_event, synthetic: true, created_at: 31.days.ago)
    old_real = create(:geofence_event, user: old_test.user, place: old_test.place, created_at: 31.days.ago)

    described_class.perform_now

    expect(GeofenceEvent.all).to contain_exactly(old_real)
  end

  it 'runs on the webhooks queue' do
    expect(described_class.new.queue_name).to eq('webhooks')
  end
end
