# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260802120000_enqueue_anomaly_recalculation.rb')

RSpec.describe EnqueueAnomalyRecalculation do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  it 'hands the work to a background job instead of doing it inline' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
  end

  it 'does not abort the migration when the job queue is unreachable' do
    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    expect { migration.up }.not_to raise_error
  end

  it 'tells the operator how to start the recalculation by hand when enqueueing failed' do
    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    migration.up

    expect(migration).to have_received(:say).with(/DataMigrations::RecalculateAnomaliesJob/)
  end
end
