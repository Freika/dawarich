# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260825120000_enqueue_country_alias_backfill.rb')

RSpec.describe EnqueueCountryAliasBackfill do
  subject(:migration) { described_class.new }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    PointSource.create!(digest: 'a' * 32)
  end

  it 're-runs the country resolution where the first pass already happened' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  # A fresh upgrade applies this migration before its dimension chain has run;
  # that chain's tail enqueues the country job with the aliases already in
  # place, and a second walker would only contend with the first.
  it 'leaves fresh installs to their own chained country run' do
    PointSource.delete_all

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  it 'does not start the re-run on Dawarich Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  it 'honours the opt-out variable' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SKIP_POINT_DIMENSION_BACKFILL').and_return('1')

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  it 'does not abort the migration when the job queue is unreachable' do
    allow(DataMigrations::BackfillPointCountryIdJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    expect { migration.up }.not_to raise_error
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    allow(DataMigrations::BackfillPointCountryIdJob)
      .to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end
end
