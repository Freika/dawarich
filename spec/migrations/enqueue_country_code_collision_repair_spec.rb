# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901070000_enqueue_country_code_collision_repair.rb')

RSpec.describe EnqueueCountryCodeCollisionRepair do
  subject(:migration) { described_class.new }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    PointSource.create!(digest: 'b' * 32)
  end

  it 'enqueues the country-link repair mode after the original backfill' do
    expect { migration.up }
      .to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
      .with(
        nil,
        DataMigrations::BackfillPointCountryIdJob::BATCH_SIZE,
        repair_collisions: true
      )
  end

  it 'leaves unstarted source backfills to their country-repair handoff' do
    PointSource.delete_all

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  it 'does not start the repair on Dawarich Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end
end
