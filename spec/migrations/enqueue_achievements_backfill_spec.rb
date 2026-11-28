# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260922120000_enqueue_achievements_backfill.rb')

RSpec.describe EnqueueAchievementsBackfill do
  subject(:migration) { described_class.new }

  it 'hands the achievements backfill to Sidekiq' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillAchievementsJob)
  end

  it 'lets the upgrade continue when the queue is unreachable' do
    allow(DataMigrations::BackfillAchievementsJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)

    expect { migration.up }.not_to raise_error
  end
end
