# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkStatsCalculatingJob, type: :job do
  describe '#perform' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }

    let(:timestamp) { DateTime.new(2024, 1, 1).to_i }

    let!(:points1) do
      (1..10).map do |i|
        create(:point, user_id: user1.id, timestamp: timestamp + i.minutes)
      end
    end

    let!(:points2) do
      (1..10).map do |i|
        create(:point, user_id: user2.id, timestamp: timestamp + i.minutes)
      end
    end

    it 'enqueues Stats::CalculatingJob for each user' do
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user1.id, 2024, 1)
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user2.id, 2024, 1)

      BulkStatsCalculatingJob.perform_now
    end
  end
end
