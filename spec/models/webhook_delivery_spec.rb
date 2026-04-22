# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookDelivery, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:webhook) }
    it { is_expected.to belong_to(:geofence_event) }
  end

  describe 'enums' do
    it do
      expect(subject).to define_enum_for(:status)
        .with_values(pending: 0, success: 1, failure: 2, retrying: 3)
        .with_prefix(:status)
    end
  end

  describe '.old' do
    it 'returns deliveries older than 30 days' do
      old = create(:webhook_delivery, created_at: 31.days.ago)
      recent = create(:webhook_delivery, created_at: 1.day.ago)
      expect(described_class.old).to include(old)
      expect(described_class.old).not_to include(recent)
    end
  end
end
