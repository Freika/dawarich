# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BackfillGenerationJob do
  let(:user) { create(:user) }
  let(:old_time) { Time.zone.local(2024, 6, 15, 10, 0, 0) }

  after do
    Tracks::BackfillScheduler.pop_range(user.id)
  end

  it 'does nothing when no range is pending' do
    expect { described_class.perform_now(user.id) }
      .not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
  end

  it 'generates a scoped bulk window for a fully historical range' do
    Tracks::BackfillScheduler.new(user.id, [old_time.to_i, (old_time + 2.days).to_i]).call

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with do |user_arg, options|
        expect(user_arg).to eq(user.id)
        expect(options[:start_at]).to eq(old_time.beginning_of_day)
        expect(options[:end_at]).to eq((old_time + 2.days).end_of_day)
        expect(options[:mode]).to eq(:bulk)
        expect(options[:untracked_only]).to be(true)
      end
  end

  it 'caps end_at at the realtime window so backfill never overlaps realtime generation' do
    recent = 10.minutes.ago
    Tracks::BackfillScheduler.new(user.id, [old_time.to_i, recent.to_i]).call

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(Tracks::ParallelGeneratorJob)
      .with do |_user_arg, options|
        expect(options[:end_at]).to be < recent.end_of_day
        expect(options[:end_at])
          .to be_within(2.minutes).of(Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago)
      end
  end

  it 'consumes the pending range after enqueueing generation' do
    Tracks::BackfillScheduler.new(user.id, [old_time.to_i]).call

    described_class.perform_now(user.id)

    expect(Tracks::BackfillScheduler.pop_range(user.id)).to be_nil
  end

  it 'reschedules the range for retry when enqueueing fails' do
    Tracks::BackfillScheduler.new(user.id, [old_time.to_i]).call
    allow(Tracks::ParallelGeneratorJob).to receive(:perform_later).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(user.id) }.not_to raise_error
    expect(Tracks::BackfillScheduler.pop_range(user.id)).to eq([old_time.to_i, old_time.to_i])
  end
end
