# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::EnqueueFullRecalculation do
  let(:user) { create(:user) }

  describe '#call' do
    it 'enqueues one calculation job per tracked month' do
      allow(user).to receive(:years_tracked).and_return([{ year: 2025, months: %w[Nov Dec] }])

      expect { described_class.new(user).call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2025, 11)
        .and have_enqueued_job(Stats::CalculatingJob).with(user.id, 2025, 12)
    end

    it 'enqueues nothing when no months are tracked' do
      allow(user).to receive(:years_tracked).and_return([])

      expect { described_class.new(user).call }.not_to have_enqueued_job(Stats::CalculatingJob)
    end
  end
end
