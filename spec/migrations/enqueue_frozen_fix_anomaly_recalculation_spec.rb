# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260823190000_enqueue_frozen_fix_anomaly_recalculation.rb')

RSpec.describe EnqueueFrozenFixAnomalyRecalculation do
  subject(:migration) { described_class.new }

  let(:queued_key) { DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY }
  let(:done_key) { DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY }
  let(:failed_key) { DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY }

  def stamped_user
    create(:user).tap do |user|
      user.update!(settings: (user.settings || {}).merge(done_key => '2026-08-02T01:00:00Z'))
    end
  end

  it 'hands the work to a background job instead of doing it inline' do
    user = create(:user)
    user.update!(settings: (user.settings || {}).merge(done_key => '2026-08-02T01:00:00Z'))

    expect { migration.up }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
  end

  it 'does not enqueue a second dispatcher when no previous run had to be cleared' do
    create(:user)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
  end

  it 'clears the stamps left by the previous recalculation so the user is picked up again' do
    user = create(:user)
    user.update!(settings: (user.settings || {}).merge(queued_key => '2026-08-02T00:00:00Z',
                                                       done_key => '2026-08-02T01:00:00Z'))

    migration.up

    expect(user.reload.settings.keys).not_to include(queued_key, done_key)
  end

  it 'clears a failure stamp so an account that gave up is retried' do
    user = create(:user)
    user.update!(settings: (user.settings || {}).merge(failed_key => '2026-08-02T02:00:00Z'))

    migration.up

    expect(user.reload.settings.keys).not_to include(failed_key)
  end

  it 'leaves unrelated settings untouched' do
    user = create(:user)
    user.update!(settings: (user.settings || {}).merge(done_key => '2026-08-02T01:00:00Z',
                                                       'timezone' => 'Europe/Berlin'))

    migration.up

    expect(user.reload.settings).to include('timezone' => 'Europe/Berlin')
  end

  it 'is a no-op for a user that was never recalculated' do
    user = create(:user)
    before_settings = user.reload.settings

    migration.up

    expect(user.reload.settings).to eq(before_settings)
  end

  it 'does not abort the migration when the job queue is unreachable' do
    stamped_user

    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    expect { migration.up }.not_to raise_error
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    stamped_user

    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end

  it 'logs how to start the recalculation by hand when enqueueing failed' do
    stamped_user

    allow(DataMigrations::RecalculateAnomaliesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    allow(Rails.logger).to receive(:error)

    migration.up

    expect(Rails.logger)
      .to have_received(:error).with(/DataMigrations::RecalculateAnomaliesJob\.perform_later/)
  end
end
