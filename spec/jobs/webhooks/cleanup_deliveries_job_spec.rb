# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::CleanupDeliveriesJob, type: :job do
  it 'deletes webhook_deliveries older than 30 days' do
    old = create(:webhook_delivery, created_at: 31.days.ago)
    recent = create(:webhook_delivery, created_at: 1.day.ago)
    described_class.new.perform
    expect(WebhookDelivery.where(id: old.id)).not_to exist
    expect(WebhookDelivery.where(id: recent.id)).to exist
  end
end
