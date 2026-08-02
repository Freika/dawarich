# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateAnomaliesJob, type: :job do
  let(:tracking_user) { create(:user) }
  let(:user_without_points) { create(:user) }
  let(:user_with_filtering_off) { create(:user, settings: { 'gps_filtering_enabled' => false }) }

  let(:user_job) { DataMigrations::RecalculateAnomaliesUserJob }

  before do
    create(:point, user: tracking_user)
    create(:point, user: user_with_filtering_off)
  end

  it 'enqueues a per-user recalculation for every user with points' do
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

  it 'skips users that a previous run already recalculated' do
    tracking_user.update!(
      settings: tracking_user.settings.merge(
        DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY => Time.current.iso8601
      )
    )

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job)
  end

  it 'is safe to run twice: the second run picks up only what is left' do
    described_class.perform_now
    perform_enqueued_jobs(only: user_job)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    straggler = create(:user)
    create(:point, user: straggler)

    expect do
      described_class.perform_now
    end.to have_enqueued_job(user_job).with(straggler.id).exactly(:once)
  end

  it 'staggers every enqueue across a window instead of firing them all at once' do
    create_list(:user, 3).each { |user| create(:point, user: user) }

    described_class.perform_now

    scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == user_job }

    expect(scheduled.size).to eq(4)
    scheduled.each do |job|
      delta = job[:at].to_f - Time.current.to_f
      expect(delta).to be >= 0
      expect(delta).to be <= described_class.stagger_window(4) + 5
    end
  end

  it 'keeps the window short for a single-user instance and caps it for a large one' do
    expect(described_class.stagger_window(1)).to eq(described_class::SECONDS_PER_USER)
    expect(described_class.stagger_window(1_000_000)).to eq(described_class::MAX_STAGGER_WINDOW_SECONDS)
  end

  it 'enqueues nothing when no user is eligible' do
    Point.delete_all

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(user_job)
  end
end
