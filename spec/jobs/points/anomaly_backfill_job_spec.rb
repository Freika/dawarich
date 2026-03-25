# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyBackfillJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    let!(:bad_point) do
      create(:point, user: user, accuracy: 500, timestamp: 6.months.ago.to_i)
    end
    let!(:good_point) do
      create(:point, user: user, accuracy: 10, timestamp: 6.months.ago.to_i + 60)
    end

    it 'marks anomalous historical points' do
      described_class.new.perform

      expect(bad_point.reload.anomaly).to be true
      expect(good_point.reload.anomaly).not_to be true
    end

    it 'processes all users' do
      user2 = create(:user)
      bad2 = create(:point, user: user2, accuracy: 500, timestamp: 3.months.ago.to_i)

      described_class.new.perform

      expect(bad2.reload.anomaly).to be true
    end

    it 'is idempotent' do
      described_class.new.perform

      expect { described_class.new.perform }.not_to raise_error
      expect(bad_point.reload.anomaly).to be true
    end
  end

  describe 'queue configuration' do
    it 'uses the low_priority queue' do
      expect(described_class.queue_name).to eq('low_priority')
    end
  end
end
