# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261026120000_enqueue_android_tower_fix_recalculation.rb')

RSpec.describe EnqueueAndroidTowerFixRecalculation do
  subject(:migration) { described_class.new }

  it 'queues the recalculation for users with coarse Android fixes' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::QueueAndroidTowerFixRecalculationJob)
  end

  it 'keeps deployment running when the queue is unavailable' do
    allow(DataMigrations::QueueAndroidTowerFixRecalculationJob).to receive(:perform_later)
      .and_raise(StandardError, 'offline')

    expect { migration.up }.not_to raise_error
  end
end
