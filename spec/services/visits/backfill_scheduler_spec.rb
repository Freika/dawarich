# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::BackfillScheduler do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'visits_suggestions_enabled' => 'true' }) }
  let(:old) { 3.days.ago.to_i }

  around { |example| freeze_time { example.run } }
  after { described_class.pop_range(user.id) }

  it 'ignores an empty batch' do
    expect { described_class.new(user.id, [nil]).call }.not_to have_enqueued_job(Visits::BackfillSuggestingJob)
  end

  it 'leaves recent points including the exact boundary on the realtime path' do
    expect { described_class.new(user.id, [6.hours.ago.to_i, 1.minute.ago.to_i]).call }
      .not_to have_enqueued_job(Visits::BackfillSuggestingJob)
    expect(described_class.pop_range(user.id)).to be_nil
  end

  it 'does not schedule for users who opted out' do
    user.update!(settings: { 'visits_suggestions_enabled' => 'false' })
    expect { described_class.new(user.id, [old]).call }.not_to have_enqueued_job(Visits::BackfillSuggestingJob)
  end

  it 'does not schedule for a missing user' do
    expect { described_class.new(-1, [old]).call }.not_to have_enqueued_job(Visits::BackfillSuggestingJob)
  end

  it 'debounces several batches into one delayed job on the existing queue' do
    expect do
      3.times { |i| described_class.new(user.id, [old + i * 60]).call }
    end.to have_enqueued_job(Visits::BackfillSuggestingJob).with(user.id).on_queue('visit_suggesting')
                                                           .at(Time.current + described_class::DEBOUNCE_DELAY).once
  end

  it 'accumulates the widest late range across several batches without recent points' do
    described_class.new(user.id, [old, old + 60, 1.minute.ago.to_i]).call
    described_class.new(user.id, [old - 1.day.to_i, old + 120]).call
    described_class.new(user.id, [old + 30]).call

    expect(described_class.pop_range(user.id)).to eq([old - 1.day.to_i, old + 120])
  end

  it 'retains only two bounds and expires both Redis keys' do
    3.times { |i| described_class.new(user.id, [old + i * 60]).call }

    Sidekiq.redis do |redis|
      expect(redis.zcard("visit_backfill_range:user:#{user.id}")).to eq(2)
      %W[visit_backfill_range:user:#{user.id} visit_backfill:user:#{user.id}].each do |key|
        expect(redis.ttl(key)).to be_between(1, described_class::REDIS_KEY_TTL.to_i)
      end
    end
  end

  it 'atomically consumes the range and allows the next batch to schedule again' do
    described_class.new(user.id, [old]).call
    expect(described_class.pop_range(user.id)).to eq([old, old])
    expect(described_class.pop_range(user.id)).to be_nil

    expect { described_class.new(user.id, [old + 60]).call }
      .to have_enqueued_job(Visits::BackfillSuggestingJob).with(user.id)
  end

  it 'leaves points older than the automatic cap to full-history redetection' do
    expect { described_class.new(user.id, [31.days.ago.to_i]).call }
      .not_to have_enqueued_job(Visits::BackfillSuggestingJob)
    expect(described_class.pop_range(user.id)).to be_nil
  end

  it 'keeps eligible points when a batch also contains points outside the cap' do
    described_class.new(user.id, [31.days.ago.to_i, old]).call
    expect(described_class.pop_range(user.id)).to eq([old, old])
  end

  it 'releases the schedule claim after enqueue failure while retaining the range' do
    configured = instance_double(ActiveJob::ConfiguredJob)
    allow(configured).to receive(:perform_later).and_raise(StandardError, 'queue unavailable')
    allow(Visits::BackfillSuggestingJob).to receive(:set).and_return(configured)
    expect { described_class.new(user.id, [old]).call }.to raise_error(StandardError, 'queue unavailable')
    allow(Visits::BackfillSuggestingJob).to receive(:set).and_call_original

    expect { described_class.new(user.id, [old + 60]).call }
      .to have_enqueued_job(Visits::BackfillSuggestingJob)
    expect(described_class.pop_range(user.id)).to eq([old, old + 60])
  end
end
