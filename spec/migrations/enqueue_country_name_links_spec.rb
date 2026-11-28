# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261108150000_enqueue_country_name_links.rb')

RSpec.describe EnqueueCountryNameLinks do
  subject(:migration) { described_class.new }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    PointSource.create!(digest: 'a' * 32)
    ActiveRecord::Base.connection.execute(
      "DELETE FROM ar_internal_metadata WHERE key = '#{described_class::ENQUEUED_KEY}'"
    )
  end

  it 'queues the link backfill' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::LinkCountryNamesJob)
  end

  it 'queues the backfill on a rerun after the job queue was unreachable' do
    allow(DataMigrations::LinkCountryNamesJob).to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    expect { migration.up }.not_to raise_error
    allow(DataMigrations::LinkCountryNamesJob).to receive(:perform_later).and_call_original

    expect { described_class.new.up }.to have_enqueued_job(DataMigrations::LinkCountryNamesJob)
  end

  it 'does not queue a second backfill when replayed' do
    2.times { described_class.new.up }

    expect(enqueued_jobs.count { |job| job[:job] == DataMigrations::LinkCountryNamesJob }).to eq(1)
  end

  it 'leaves fresh installs alone' do
    PointSource.delete_all

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::LinkCountryNamesJob)
  end

  it 'does not start on Dawarich Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::LinkCountryNamesJob)
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    allow(DataMigrations::LinkCountryNamesJob).to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end
end
