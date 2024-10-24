# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkStatsCalculatingJob, type: :job do
  describe '#perform' do
    it 'enqueues Stats::CalculatingJob for each user' do
      user1 = create(:user)
      user2 = create(:user)
      user3 = create(:user)

      expect(Stats::CalculatingJob).to receive(:perform_later).with(user1.id)
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user2.id)
      expect(Stats::CalculatingJob).to receive(:perform_later).with(user3.id)

      BulkStatsCalculatingJob.perform_now
    end
  end
end
