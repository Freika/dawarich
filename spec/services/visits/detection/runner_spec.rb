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

  it 'respects a user tombstone across re-runs (I1)' do
    seed_scenario(:home_gap)
    run

    user.visits.first.update!(deleted_at: Time.current)
    created = run

    expect(created).to be_empty
    expect(user.visits.active.count).to eq(0)
  end
end
