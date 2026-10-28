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
end
