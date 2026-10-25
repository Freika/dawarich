# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookDelivery do
  it 'finds deliveries older than 30 days' do
    old = create(:webhook_delivery, created_at: 31.days.ago)
    create(:webhook_delivery, webhook: old.webhook, created_at: 29.days.ago)

    expect(described_class.old).to contain_exactly(old)
  end
end
