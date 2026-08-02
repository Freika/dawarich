# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateAnomaliesJob, type: :job do
  let(:tracking_user) { create(:user) }
  let!(:user_without_points) { create(:user) }
  let(:user_with_filtering_off) { create(:user, settings: { 'gps_filtering_enabled' => false }) }

  let(:user_job) { DataMigrations::RecalculateAnomaliesUserJob }
  let(:queued_key) { user_job::QUEUED_SETTINGS_KEY }

  before do
    create(:point, user: tracking_user)
    create(:point, user: user_with_filtering_off)
  end

  it 'hands a user with points to the per-user rebuild' do
    expect do
      described_class.perform_now
    end.to have_enqueued_job(user_job).with(tracking_user.id).exactly(:once)
  end

  it 'skips users who have no points' do
    described_class.perform_now

    expect(user_job).not_to have_been_enqueued.with(user_without_points.id)
  end

  it 'skips users who turned GPS filtering off, whose flags must stay as they are' do
    described_class.perform_now

    expect(user_job).not_to have_been_enqueued.with(user_with_filtering_off.id)
  end

  it 'never runs more users at once than there are slots' do
    create_list(:user, 5).each { |user| create(:point, user: user) }

    described_class.perform_now

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == user_job }
    expect(enqueued).to eq(described_class::CONCURRENCY)
  end

  it 'hands out exactly one more user when a finished job asks for a slot' do
    create_list(:user, 5).each { |user| create(:point, user: user) }

    expect do
      described_class.perform_now(limit: 1)
    end.to have_enqueued_job(user_job).exactly(:once)
  end

  it 'marks the users it hands out so a second pass cannot pick them up again' do
    described_class.perform_now

    expect(tracking_user.reload.settings[queued_key]).to be_present

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job)
  end

  it 'marks a skipped user too, so nothing reports them waiting forever' do
    described_class.perform_now

    expect(user_with_filtering_off.reload.settings[queued_key]).to be_present
  end

  it 'picks up a straggler on a later pass' do
    described_class.perform_now
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    straggler = create(:user)
    create(:point, user: straggler)

    expect do
      described_class.perform_now
    end.to have_enqueued_job(user_job).with(straggler.id).exactly(:once)
  end

  it 'enqueues nothing when no user is eligible' do
    Point.delete_all

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job)
  end

  it 'skips a user another dispatcher already claimed' do
    tracking_user.update!(settings: tracking_user.settings.merge(queued_key => Time.current.iso8601))

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job).with(tracking_user.id)
  end

  # The scan and the claim are separate round trips, so a concurrent dispatcher
  # can take the user in between. The claim has to notice and drop them.
  it 'does not hand out a user claimed between the scan and the claim' do
    allow_any_instance_of(described_class).to receive(:next_users).and_return([[tracking_user.id], []])
    tracking_user.update!(settings: tracking_user.settings.merge(queued_key => Time.current.iso8601))

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job)
  end

  it 'releases its claim when the enqueue fails, so a later pass can retry' do
    allow(ActiveJob).to receive(:perform_all_later).and_raise(StandardError, 'redis down')

    expect { described_class.perform_now }.to raise_error(StandardError)

    expect(tracking_user.reload.settings).not_to have_key(queued_key)
  end

  it 'asks for another pass when it loses the claim race, so no slot is lost' do
    allow_any_instance_of(described_class).to receive(:next_users).and_return([[tracking_user.id], []])
    tracking_user.update!(settings: tracking_user.settings.merge(queued_key => Time.current.iso8601))

    expect do
      described_class.perform_now(limit: 1)
    end.to have_enqueued_job(described_class).with(limit: 1)
  end
end
