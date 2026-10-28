# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261028110000_enqueue_thematic_achievements_backfill.rb')

RSpec.describe EnqueueThematicAchievementsBackfill do
  it 'silently checks all eligible users, including those with current exploration' do
    expect { described_class.new.up }.to have_enqueued_job(Achievements::BulkCheckJob)
      .with(notify: false, force: true)
  end

  it 'keeps upgrades available when the background queue is unreachable' do
    allow(Achievements::BulkCheckJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

    expect { described_class.new.up }.not_to raise_error
  end

  it 'does not enqueue a second fleet check when replayed' do
    2.times { described_class.new.up }

    expect(enqueued_jobs.count { |job| job[:job] == Achievements::BulkCheckJob }).to eq(1)
  end

  it 'can retry the enqueue after a queue failure' do
    allow(Achievements::BulkCheckJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    described_class.new.up
    allow(Achievements::BulkCheckJob).to receive(:perform_later).and_call_original

    expect { described_class.new.up }.to have_enqueued_job(Achievements::BulkCheckJob)
  end
end
