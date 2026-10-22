# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::Runner do
  let(:user) { create(:user) }
  let(:start_time) { Time.zone.parse('2026-01-05 09:00:00 UTC') }

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: true, store_geodata?: false)
    allow(Geocoder).to receive(:search).and_return([])
  end

  def seed_scenario(name, at: start_time)
    scenario = VisitScenarioGenerator.scenario(name, start_time: at)

    scenario[:points].each do |p|
      create(:point, user: user, latitude: p[:lat], longitude: p[:lon],
                     lonlat: "POINT(#{p[:lon]} #{p[:lat]})",
                     timestamp: p[:timestamp], accuracy: p[:accuracy].round,
                     velocity: p[:velocity])
    end

    track = create(:track, user: user)
    scenario[:segments].each do |s|
      create(:track_segment, track: track, transportation_mode: s[:mode],
                             confidence_score: s[:confidence_score],
                             start_at: Time.zone.at(s[:start_ts]),
                             end_at: Time.zone.at(s[:end_ts]))
    end

    scenario
  end

  def run(from: start_time.to_i - 3600, to: start_time.to_i + (2 * 24 * 3600))
    described_class.new(user, start_at: from, end_at: to).call
  end

  it 'turns the home-gap scenario into ONE visit spanning the silence' do
    scenario = seed_scenario(:home_gap)

    created = run

    expect(created.size).to eq(1)
    visit = created.first
    expected = scenario[:expected][:stays].first
    expect(visit.started_at.to_i).to eq(expected[:start_ts])
    expect(visit.ended_at.to_i).to be_within(60).of(expected[:end_ts])
    expect((visit.ended_at - visit.started_at) / 3600.0).to be > 4
    expect(visit.detection_version).to eq(Visits::Detection::VERSION)
    expect(visit.confidence).to be_present
  end

  it 'creates zero visits for the drive-carving scenario' do
    seed_scenario(:drive_carving)

    expect(run).to be_empty
    expect(user.visits.count).to eq(0)
  end

  it 'creates only the real stop in the dark-dinner scenario — nothing at the resume location' do
    scenario = seed_scenario(:dark_dinner)

    created = run

    expect(created.size).to eq(1)
    expected = scenario[:expected][:stays].first
    expect(created.first.started_at.to_i).to be_within(120).of(expected[:start_ts])
    expect(created.first.ended_at.to_i).to be_within(120).of(expected[:end_ts])
  end

  it 'snaps the cold-start visit to the end of the drive' do
    scenario = seed_scenario(:cold_start)

    created = run

    expect(created.size).to eq(1)
    expect(created.first.started_at.to_i).to eq(scenario[:expected][:stays].first[:start_ts])
  end

  it 'produces exactly one visit across a day boundary' do
    seed_scenario(:day_boundary, at: Time.zone.parse('2026-01-05 23:00:00 UTC'))

    expect(run.size).to eq(1)
  end

  it 'stitches one visit across a detection batch boundary' do
    edge = Time.zone.parse('2026-01-31 23:00:00 UTC')
    seed_scenario(:batch_boundary, at: edge)

    created = run(from: Time.zone.parse('2026-01-01 00:00:00 UTC').to_i,
                  to: Time.zone.parse('2026-02-28 00:00:00 UTC').to_i)

    expect(created.size).to eq(1)
    expect(created.first.started_at.to_i).to be_within(120).of(edge.to_i)
    expect((created.first.ended_at - created.first.started_at) / 60).to be_within(10).of(120)
  end

  it 'splits a window over the candidate cap instead of skipping it' do
    scenario = seed_scenario(:home_gap)
    stub_const('Visits::Detection::CandidateLoader::MAX_CANDIDATE_POINTS', scenario[:points].size - 1)
    runner = described_class.new(user, start_at: start_time.to_i - 3600, end_at: start_time.to_i + (2 * 24 * 3600))

    created = runner.call

    expect(runner.skipped_ranges).to be_empty
    expect(created.size).to eq(1)
    expect(created.first.started_at.to_i).to eq(scenario[:expected][:stays].first[:start_ts])
  end

  it 'still reports a window that stays over the cap at the smallest split' do
    seed_scenario(:home_gap)
    stub_const('Visits::Detection::CandidateLoader::MAX_CANDIDATE_POINTS', 0)
    runner = described_class.new(user, start_at: start_time.to_i - 3600, end_at: start_time.to_i + (2 * 24 * 3600))

    expect(runner.call).to be_empty
    expect(runner.skipped_ranges).not_to be_empty
  end

  it 'never stitches across a point-less anchor sitting in the silence' do
    month_edge = Time.zone.parse('2026-02-01 00:00:00')
    [-30, -27, -24, -21, -18, -15].each do |m|
      create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)',
                     timestamp: (month_edge + m.minutes).to_i, accuracy: 10)
    end
    [30, 33, 36, 39, 42, 45].each do |m|
      create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)',
                     timestamp: (month_edge + m.minutes).to_i, accuracy: 10)
    end
    import = create(:import, user: user)
    anchor = create(:visit, user: user, status: :suggested,
                            started_at: month_edge - 10.minutes, ended_at: month_edge + 10.minutes,
                            duration: 20, name: 'Imported stop')
    anchor.update_columns(import_id: import.id)

    created = run(from: Time.zone.parse('2026-01-01 00:00:00').to_i,
                  to: Time.zone.parse('2026-02-28 00:00:00').to_i)

    created.each do |visit|
      overlap = [visit.ended_at.to_i, anchor.ended_at.to_i].min -
                [visit.started_at.to_i, anchor.started_at.to_i].max
      expect(overlap).to be <= 0
    end
  end

  it 'rescores the stitched visit from the merged evidence' do
    month_edge = Time.zone.parse('2026-02-01 00:00:00')
    first_fix = month_edge - 15.minutes
    25.times do |i|
      create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                     lonlat: 'POINT(12.3712 51.3402)',
                     timestamp: first_fix.to_i + (i * 180), accuracy: 10)
    end

    created = run(from: Time.zone.parse('2026-01-01 00:00:00').to_i,
                  to: Time.zone.parse('2026-02-28 00:00:00').to_i)

    expect(created.size).to eq(1)
    expect(created.first.confidence_breakdown['dwell'].to_f).to eq(1.0)
  end

  it 'is idempotent across full re-runs' do
    seed_scenario(:home_gap)

    run
    first = user.visits.order(:started_at).pluck(:started_at, :ended_at, :name)
    run
    second = user.visits.order(:started_at).pluck(:started_at, :ended_at, :name)

    expect(second).to eq(first)
  end

  it 'labels a stay inside a user area — area visit counts keep working without the old area detector' do
    area = create(:area, user: user, latitude: 51.3402, longitude: 12.3712, radius: 200, name: 'Home Zone')
    seed_scenario(:home_gap)

    created = run

    expect(created.first.area).to eq(area)
    expect(created.first.name).to eq('Home Zone')
    expect(user.visits.where(area_id: area.id).count).to eq(1)
  end

  it 'clears stale machine visits the data no longer supports' do
    create(:visit, user: user, status: :suggested,
                   started_at: start_time + 1.hour, ended_at: start_time + 2.hours, duration: 60)
    create(:point, user: user, latitude: 51.3402, longitude: 12.3712,
                   lonlat: 'POINT(12.3712 51.3402)', timestamp: start_time.to_i + 60, accuracy: 10)

    created = run

    expect(created).to be_empty
    expect(user.visits.count).to eq(0)
  end

  it 'does not truncate a stay when a narrow window cuts through it' do
    seed_scenario(:home_gap)
    run
    before_rerun = user.visits.order(:started_at).pluck(:started_at, :ended_at)

    mid_visit = before_rerun.first.first.to_i + 2.hours.to_i
    described_class.new(user, start_at: mid_visit, end_at: mid_visit + 6.hours).call

    expect(user.visits.order(:started_at).pluck(:started_at, :ended_at)).to eq(before_rerun)
  end

  describe 'a stay that fell silent before the window opened' do
    let(:home) { [51.3402, 12.3712] }
    let(:arrived_at) { Time.zone.parse('2026-01-05 19:00:00 UTC') }
    let(:resumed_at) { arrived_at + 9.hours }

    def fix(at, lat, lon)
      create(:point, user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: at.to_i, accuracy: 10)
    end

    def run_realtime_window(ending_at)
      described_class.new(user, start_at: ending_at - 6.hours, end_at: ending_at).call
    end

    def resume_at_home
      (0..3).each { |i| fix(resumed_at + i.minutes, home[0] + ((i % 3) * 0.00001), home[1]) }
      run_realtime_window(resumed_at + 3.minutes)
    end

    def visit_tuples
      user.visits.reload.order(:started_at).pluck(:status, :started_at, :ended_at)
    end

    before do
      (0..6).each { |i| fix(arrived_at + i.minutes, home[0] + ((i % 3) * 0.00001), home[1]) }
      run_realtime_window(arrived_at + 6.minutes)
    end

    it 'bridges the silence when tracking resumes at the same place' do
      resume_at_home

      expect(user.visits.count).to eq(1)
      expect(user.visits.first.started_at).to eq(arrived_at)
      expect(user.visits.first.ended_at).to be >= resumed_at + 3.minutes
    end

    it 'keeps the stay apart when tracking resumed elsewhere first' do
      fix(arrived_at + 4.hours, 51.35, 12.38)
      resume_at_home

      expect(user.visits.order(:started_at).first.ended_at).to eq(arrived_at + 6.minutes)
    end

    it 'trims around a confirmed visit in the silence like a full re-detection' do
      create(:visit, user: user, status: :confirmed,
                     started_at: arrived_at + 2.hours, ended_at: arrived_at + 3.hours, duration: 60)
      resume_at_home
      incremental = visit_tuples

      Visits::Detection::HistoryRedetect.new(user).call

      expect(incremental).to eq(visit_tuples)
    end
  end

  it 'respects a user tombstone across re-runs (I1)' do
    seed_scenario(:home_gap)
    run

    user.visits.first.update!(deleted_at: Time.current)
    created = run

    expect(created).to be_empty
    expect(user.visits.active.count).to eq(0)
  end

  it 'batches point geodata reads across stays without changing detected visits' do
    3.times { |i| seed_scenario(:home_gap, at: start_time + i * 3.days) }
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql]
      queries << sql if sql.start_with?('SELECT') && sql.include?('"points"."geodata" !=') &&
                        sql.include?('FROM "points"')
    end
    created = described_class.new(user, start_at: start_time.to_i - 3600,
                                 end_at: (start_time + 8.days).to_i).call
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(created.size).to eq(3)
    expect(queries.size).to be <= 1
    first = user.visits.order(:started_at).pluck(:started_at, :ended_at, :name, :confidence, :confidence_breakdown)
    described_class.new(user, start_at: start_time.to_i - 3600, end_at: (start_time + 8.days).to_i).call
    expect(user.visits.order(:started_at).pluck(:started_at, :ended_at, :name, :confidence,
                                                :confidence_breakdown)).to eq(first)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it 'stitches from projected centers without loading full point rows per visit' do
    3.times { |i| seed_scenario(:home_gap, at: start_time + i * 3.days) }
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql]
      queries << sql if sql.start_with?('SELECT') && sql.include?('FROM "points"') &&
                        (sql.include?('"points"."raw_data"') || sql.include?('"points".*'))
    end
    created = described_class.new(user, start_at: start_time.to_i - 3600,
                                 end_at: (start_time + 8.days).to_i).call

    expect(created.size).to eq(3)
    expect(queries).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
