# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260811120000_enqueue_leaped_point_recalculation.rb')

RSpec.describe EnqueueLeapedPointRecalculation do
  subject(:migration) { described_class.new }

  let(:stamp_keys) do
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end

  it 'strips every completion stamp so the dispatcher hands users out again' do
    user = create(:user)
    user.update_columns(
      settings: (user.settings || {}).merge(
        stamp_keys[0] => '2026-08-02T12:00:00Z',
        stamp_keys[1] => '2026-08-02T13:00:00Z',
        stamp_keys[2] => '2026-08-02T14:00:00Z'
      )
    )

    migration.up

    settings = user.reload.settings
    stamp_keys.each { |key| expect(settings).not_to have_key(key) }
  end

  it 'leaves every other settings key untouched' do
    user = create(:user)
    user.update_columns(
      settings: (user.settings || {}).merge(
        'maps' => { 'distance_unit' => 'km' },
        stamp_keys[1] => '2026-08-02T13:00:00Z'
      )
    )

    migration.up

    expect(user.reload.settings['maps']).to eq({ 'distance_unit' => 'km' })
  end

  it 'runs without a wrapping transaction so stamps are committed before the job can see them' do
    expect(described_class.disable_ddl_transaction).to be true
  end

  it 'hands the work to a background job instead of doing it inline' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
  end

  it 'does not abort the migration when the job queue is unreachable' do
    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    expect { migration.up }.not_to raise_error
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end

  it 'logs how to start the recalculation by hand when enqueueing failed' do
    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    allow(Rails.logger).to receive(:error)

    migration.up

    expect(Rails.logger)
      .to have_received(:error).with(/DataMigrations::RecalculateAnomaliesJob\.perform_later/)
  end
end
