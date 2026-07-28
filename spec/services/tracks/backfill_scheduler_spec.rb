# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BackfillScheduler do
  let(:user) { create(:user) }
  let(:window_start) { Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago.to_i }

  after do
    described_class.pop_range(user.id)
  end

  describe '#call' do
    it 'does nothing for an empty batch' do
      expect { described_class.new(user.id, []).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end

    it 'does nothing when every timestamp is inside the lookback window' do
      expect { described_class.new(user.id, [window_start + 60, window_start + 120]).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end

    it 'does nothing when the earliest timestamp sits exactly on the window boundary' do
      expect { described_class.new(user.id, [window_start, window_start + 60]).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end

    it 'schedules a backfill job when the earliest timestamp predates the window' do
      expect { described_class.new(user.id, [window_start - 1, window_start + 60]).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end
  end

  describe '#pop_range' do
    let(:day) { Time.zone.local(2024, 6, 15, 12, 0, 0).to_i }

    it 'returns the widest min/max accumulated across a burst' do
      described_class.new(user.id, [day, day + 100]).call
      described_class.new(user.id, [day - 86_400, day + 100]).call

      expect(described_class.pop_range(user.id)).to eq([day - 86_400, day + 100])
    end

    it 'consumes the range so a redelivered job sees nothing' do
      described_class.new(user.id, [day]).call

      expect(described_class.pop_range(user.id)).to eq([day, day])
      expect(described_class.pop_range(user.id)).to be_nil
    end
  end
end
