# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit detection across an overnight tracking silence' do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:home) { [51.3402, 12.3712] }
  let(:arrived_at) { Time.zone.parse('2026-01-05 19:00:00 UTC') }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: true, store_geodata?: false)
    allow(Geocoder).to receive(:search).and_return([])
    allow(Geocoding::Config).to receive(:for).and_return(Geocoding::Config.default_fallback)
    Visits::RealtimeDebouncer.new(user.id).clear
  end

  def fix(at, lat, lon, jitter)
    { ts: at.to_i, lat: lat + (jitter * 0.00001), lon: lon + (jitter * 0.00001) }
  end

  # Home at 19:00, phone silent for nine hours, a few fixes at 04:00 and a walk away.
  def stream
    arrival = (0..6).map { |i| fix(arrived_at + i.minutes, *home, i % 3) }
    departure = (0..3).map { |i| fix(arrived_at + 9.hours + i.minutes, *home, i % 3) }
    walk = (1..10).map do |i|
      fix(arrived_at + 9.hours + 3.minutes + (i * 30), home[0], home[1] + (i * 0.0006), 0)
    end
    arrival + departure + walk
  end

  def create_point(fix)
    create(:point, user: user, lonlat: "POINT(#{fix[:lon]} #{fix[:lat]})", timestamp: fix[:ts], accuracy: 10)
  end

  def run_due_visit_jobs
    due = enqueued_jobs.select do |job|
      job['job_class'] == 'VisitSuggestingJob' &&
        (job['scheduled_at'].nil? || Time.zone.parse(job['scheduled_at'].to_s) <= Time.current)
    end
    due.each do |job|
      enqueued_jobs.delete(job)
      VisitSuggestingJob.perform_now(**ActiveJob::Arguments.deserialize(job['arguments']).first.symbolize_keys)
    end
  end

  def run_nightly_day_windows
    [arrived_at.to_date, arrived_at.to_date + 1].each do |day|
      VisitSuggestingJob.perform_now(
        user_id: user.id, start_at: day.beginning_of_day.iso8601, end_at: day.end_of_day.iso8601
      )
    end
  end

  def detected_state
    {
      visits: user.visits.reload.order(:started_at).pluck(:started_at, :ended_at).map { |a, b| [a.to_i, b.to_i] },
      claimed: Point.where(user_id: user.id).where.not(visit_id: nil).count
    }
  end

  def full_redetection_state
    Visits::Detection::HistoryRedetect.new(user).call
    detected_state
  end

  it 'realtime detection bridges the silence the way a full re-detection does' do
    stream.each do |fix|
      travel_to(Time.zone.at(fix[:ts])) do
        create_point(fix)
        Visits::RealtimeDebouncer.new(user.id).trigger
        run_due_visit_jobs
      end
    end
    travel_to(Time.zone.at(stream.last[:ts]) + 1.hour) { run_due_visit_jobs }

    realtime = detected_state

    expect(realtime[:visits].size).to eq(1)
    expect(realtime).to eq(full_redetection_state)
  end

  def run_day_window(day)
    VisitSuggestingJob.perform_now(
      user_id: user.id, start_at: day.beginning_of_day.iso8601, end_at: day.end_of_day.iso8601
    )
  end

  it 'bridges when the arrival visit is attributed to a place away from its fixes' do
    stream.each { |fix| create_point(fix) }
    run_day_window(arrived_at.to_date)
    far_place = create(:place, user: user, latitude: home[0] + 0.003, longitude: home[1],
                               lonlat: "POINT(#{home[1]} #{home[0] + 0.003})")
    user.visits.update_all(place_id: far_place.id)

    run_day_window(arrived_at.to_date + 1)

    visits = detected_state[:visits]
    expect(visits.size).to eq(1)
    expect(visits.first.first).to eq(arrived_at.to_i)
    expect(visits.first.last).to be >= (arrived_at + 9.hours).to_i
  end

  it 'bridges past an anomalous fix recorded right after the arrival' do
    stream.each { |fix| create_point(fix) }
    create(:point, user: user, lonlat: "POINT(#{home[1] + 0.05} #{home[0]})",
                   timestamp: (arrived_at + 7.minutes).to_i, accuracy: 10, anomaly: true)

    run_nightly_day_windows

    visits = detected_state[:visits]
    expect(visits.size).to eq(1)
    expect(visits.first.first).to eq(arrived_at.to_i)
    expect(visits.first.last).to be >= (arrived_at + 9.hours).to_i
  end

  it 'nightly per-day windows bridge the silence the way a full re-detection does' do
    stream.each { |fix| create_point(fix) }

    run_nightly_day_windows
    nightly = detected_state

    expect(nightly[:visits].size).to eq(1)
    expect(nightly).to eq(full_redetection_state)
  end
end
