# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::BulkCheckJob do
  include ActiveJob::TestHelper

  before { Flipper.enable(:achievements) }

  after { Flipper.disable(:achievements) }

  def eligible_user(status: :active)
    user = create(:user, status: status)
    create(:point, user: user)
    user
  end

  it 'enqueues a check for active and trial users only' do
    active = eligible_user
    trial = eligible_user(status: :trial)
    eligible_user(status: :inactive)

    expect { described_class.perform_now }
      .to have_enqueued_job(Achievements::CheckJob).with(active.id, notify: true, force: false).once
      .and have_enqueued_job(Achievements::CheckJob).with(trial.id, notify: true, force: false).once
  end

  it 'staggers batches and can suppress notifications for backfills' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    users = Array.new(2) { eligible_user }

    described_class.perform_now(notify: false)

    expect(Achievements::CheckJob).to have_been_enqueued.with(users.first.id, notify: false, force: false)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Achievements::CheckJob }
    waits = enqueued.map { |j| j[:at] }.compact
    expect(waits.uniq.size).to be > 1
  end

  it 'enqueues nothing while the feature flag is disabled' do
    Flipper.disable(:achievements)
    eligible_user

    expect { described_class.perform_now }.not_to have_enqueued_job(Achievements::CheckJob)
  end

  it 'still runs a forced backfill while the feature flag is disabled' do
    Flipper.disable(:achievements)
    user = eligible_user

    expect { described_class.perform_now(notify: false, force: true) }
      .to have_enqueued_job(Achievements::CheckJob).with(user.id, notify: false, force: true).once
  end

  it 'queues only users without progress from the current calculation version during rollout' do
    current = eligible_user
    stale = eligible_user
    new_user = eligible_user(status: :trial)
    version = Achievements::RegionSetChecker::CALCULATION_VERSION
    create(:achievement_progress, user: current, achievement_key: Achievements::Progress::EXPLORATION_KEY,
                                  state: { 'calculation_version' => version })
    create(:achievement_progress, user: stale, achievement_key: Achievements::Progress::EXPLORATION_KEY, state: {})

    described_class.perform_now(notify: false, force: true, stale_only: true)

    expect(Achievements::CheckJob).not_to have_been_enqueued.with(current.id, notify: false, force: true)
    expect(Achievements::CheckJob).to have_been_enqueued.with(stale.id, notify: false, force: true).once
    expect(Achievements::CheckJob).to have_been_enqueued.with(new_user.id, notify: false, force: true).once
  end

  it 'ignores users without usable points' do
    user = create(:user, status: :active)

    described_class.perform_now(force: true)

    expect(Achievements::CheckJob).not_to have_been_enqueued.with(user.id, notify: true, force: true)
  end
end
