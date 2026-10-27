# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::BackfillSuggestingJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, :pro_plan, settings: {
             'visits_suggestions_enabled' => 'true', 'visit_radius_meters' => 100,
             'visit_min_points' => 3, 'visit_min_duration_minutes' => 2,
             'live_map_enabled' => false, 'timezone' => 'Etc/UTC'
           })
  end
  let(:old) { 3.days.ago.change(hour: 12) }

  around do |example|
    Time.use_zone('Etc/UTC') do
      travel_to(Time.utc(2026, 10, 20, 12)) { example.run }
    end
  end

  before do
    clear_enqueued_jobs
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([])
    Visits::RealtimeDebouncer.new(user.id).clear
    Tracks::RealtimeDebouncer.new(user.id).clear
  end

  after do
    Visits::BackfillScheduler.pop_range(user.id)
    Visits::RealtimeDebouncer.new(user.id).clear
    Tracks::RealtimeDebouncer.new(user.id).clear
    clear_enqueued_jobs
  end

  def fixes(ending:, count: 5, interval: 60)
    Array.new(count) do |i|
      {
        lonlat: 'POINT(-140.12345 -40.12345)',
        timestamp: ending.to_i - ((count - 1 - i) * interval),
        accuracy: 30, velocity: 0, tracker_id: 'synthetic-backfill'
      }
    end
  end

  def ingest(rows, mode: :bulk)
    Points::Intake.call(user_id: user.id, payloads: rows, mode: mode)
  end

  def queue_range(timestamps = [old.to_i])
    Visits::BackfillScheduler.new(user.id, timestamps).call
  end

  it 'does nothing without a pending range' do
    expect(VisitSuggestingJob).not_to receive(:perform_now)
    described_class.perform_now(user.id)
  end

  it 'rechecks opt-in at execution and consumes the pending range' do
    queue_range
    user.update!(settings: user.settings.merge('visits_suggestions_enabled' => 'false'))
    expect(VisitSuggestingJob).not_to receive(:perform_now)
    described_class.perform_now(user.id)
    expect(Visits::BackfillScheduler.pop_range(user.id)).to be_nil
  end

  it 'ignores a user deleted after scheduling' do
    queue_range
    user.destroy!
    expect(VisitSuggestingJob).not_to receive(:perform_now)
    expect { described_class.perform_now(user.id) }.not_to raise_error
  end

  it 'pads both edges of the capture range by six hours' do
    queue_range([old.to_i, (old + 1.hour).to_i])
    expect(VisitSuggestingJob).to receive(:perform_now).with(
      user_id: user.id, start_at: old - 6.hours, end_at: old + 7.hours
    )
    described_class.perform_now(user.id)
  end

  it 'caps padded work at thirty days and the current time' do
    queue_range([30.days.ago.to_i, (6.hours.ago - 1.second).to_i])
    expect(VisitSuggestingJob).to receive(:perform_now).with(
      user_id: user.id, start_at: 30.days.ago, end_at: Time.current - 1.second
    )
    described_class.perform_now(user.id)
  end

  it 'discards a range that ages beyond the cap while queued' do
    queue_range([30.days.ago.to_i])
    travel 1.day
    expect(VisitSuggestingJob).not_to receive(:perform_now)
    described_class.perform_now(user.id)
  end

  it 'assembles a stay that began before the earliest uploaded late point' do
    rows = fixes(ending: old, count: 5)
    ingest(rows.first(4))
    ingest(rows.last(1), mode: :realtime)

    described_class.perform_now(user.id)

    expect(user.visits.suggested.count).to eq(1)
    expect(user.visits.suggested.first.started_at.to_i).to eq(rows.first[:timestamp])
    expect(user.visits.suggested.first.ended_at.to_i).to eq(rows.last[:timestamp])
  end

  it 'reruns an already detected window without duplicating visits' do
    rows = fixes(ending: old)
    ingest(rows, mode: :realtime)
    described_class.perform_now(user.id)
    expect(user.visits.suggested.count).to eq(1)
    queue_range(rows.map { |row| row[:timestamp] })

    described_class.perform_now(user.id)

    expect(user.visits.suggested.count).to eq(1)
    expect(user.visits.suggested.first.started_at.to_i).to eq(rows.first[:timestamp])
    expect(user.visits.suggested.first.ended_at.to_i).to eq(rows.last[:timestamp])
  end
end
