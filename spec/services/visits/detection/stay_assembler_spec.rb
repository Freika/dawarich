# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::StayAssembler do
  let(:policy) do
    Visits::Detection::Policy.new(
      stay_radius_m: 100, min_dwell_s: 300, min_points: 3, merge_gap_s: 900
    )
  end
  let(:base_ts) { 1_700_000_000 }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  def north(meters) = meters / 111_320.0
  def east(meters)  = meters / (111_320.0 * Math.cos(lat0 * Math::PI / 180))

  def pt(id, at:, dnorth: 0.0, deast: 0.0, accuracy: 10)
    Visits::Detection::CandidateLoader::Pt.new(
      id, lat0 + north(dnorth), lon0 + east(deast), base_ts + at, accuracy
    )
  end

  def fragment(ids, start_s, end_s, deast: 0.0, bridged_s: 0, corroborated: false)
    {
      point_ids: ids, start_ts: base_ts + start_s, end_ts: base_ts + end_s,
      center_lat: lat0, center_lon: lon0 + east(deast), count: ids.size,
      bridged_s: bridged_s, corroborated: corroborated
    }
  end

  def assemble(fragments, points)
    described_class.new(policy).call(fragments, points.index_by(&:id))
  end

  it 'keeps a dark-venue stay whose evidence sits at the snapped-off edges' do
    # One fix on arrival, four reacquired on departure — the show happened in
    # the dark. Departure snapping moved the end before the trailing fixes.
    points = [pt(1, at: 0), pt(2, at: 4700), pt(3, at: 4730),
              pt(4, at: 4760), pt(5, at: 4800)]
    snapped = fragment([1, 2, 3, 4, 5], 0, 4690)

    result = assemble([snapped], points)

    expect(result.size).to eq(1)
    expect(result.first[:point_ids]).to eq([1, 2, 3, 4, 5])
    expect(result.first[:count]).to eq(5)
  end

  def pre_pipeline(scenario)
    points = as_detection_points(scenario[:points])
    swept = Visits::Detection::DwellSweep.new(policy).call(points)
    bridged = Visits::Detection::GapBridger.new(policy).call(swept)
    segments = as_detection_segments(scenario[:segments])
    reconciled = Visits::Detection::MovementReconciler.new(policy).call(bridged, segments)
    [reconciled, points]
  end

  it 'merges same-place fragments split by a brief excursion (re-entry)' do
    points = (1..6).map { |i| pt(i, at: i * 60) } + (7..12).map { |i| pt(i, at: 600 + (i * 60)) }
    fragments = [fragment((1..6).to_a, 60, 360), fragment((7..12).to_a, 1020, 1320)]

    stays = assemble(fragments, points)

    expect(stays.size).to eq(1)
    expect(stays.first[:point_ids]).to eq((1..12).to_a)
    expect(stays.first[:start_ts]).to eq(base_ts + 60)
    expect(stays.first[:end_ts]).to eq(base_ts + 1320)
  end

  it 'refuses to merge across more than the merge gap or across distance' do
    early = (1..6).map { |i| pt(i, at: i * 60) }
    late = (7..12).map { |i| pt(i, at: 1261 + ((i - 7) * 60)) }
    far_apart_time = [fragment((1..6).to_a, 0, 360), fragment((7..12).to_a, 360 + 901, 2500)]
    far_apart_space = [fragment((1..6).to_a, 0, 360), fragment((7..12).to_a, 600, 1200, deast: 300.0)]

    expect(assemble(far_apart_time, early + late).size).to eq(2)
    expect(assemble(far_apart_space, (1..12).map { |i| pt(i, at: i * 100) }).size).to eq(2)
  end

  it 'drops fragments below min dwell or min points — and only here' do
    points = (1..5).map { |i| pt(i, at: i * 10) }
    short = fragment((1..5).to_a, 10, 50)
    sparse = fragment([1, 2], 10, 400)

    expect(assemble([short], points)).to be_empty
    expect(assemble([sparse], points)).to be_empty
  end

  it 'counts bridged silence toward dwell' do
    points = [pt(1, at: 0), pt(2, at: 60), pt(3, at: 1500)]
    bridged = fragment([1, 2, 3], 0, 1500, bridged_s: 1380)

    stays = assemble([bridged], points)

    expect(stays.size).to eq(1)
    expect(stays.first[:bridged_s]).to eq(1380)
  end

  it 'holds the duration invariant and recomputes center and radius from points' do
    points = [pt(1, at: 0), pt(2, at: 120, dnorth: 40.0), pt(3, at: 400, dnorth: 80.0)]
    stays = assemble([fragment([1, 2, 3], 0, 400)], points)

    stay = stays.first
    expect(stay[:duration_s]).to eq(stay[:end_ts] - stay[:start_ts])
    expect(stay[:center_lat]).to be_between(lat0, lat0 + north(80.0))
    expect(stay[:radius]).to be >= 15
  end

  it 'carries corroboration through merges' do
    points = (1..12).map { |i| pt(i, at: i * 60) }
    fragments = [
      fragment((1..6).to_a, 60, 360, corroborated: false),
      fragment((7..12).to_a, 600, 1200, corroborated: true)
    ]

    expect(assemble(fragments, points).first[:corroborated]).to be(true)
  end

  it 'resolves the re-entry scenario end to end as one café stay' do
    scenario = VisitScenarioGenerator.scenario(:reentry, start_time: Time.zone.at(base_ts))
    reconciled, points = pre_pipeline(scenario)

    stays = assemble(reconciled, points)

    expect(stays.size).to eq(1)
    expected = scenario[:expected][:stays].first
    expect(stays.first[:duration_s]).to be_between(45 * 60, 60 * 60)
    expect(stays.first[:start_ts]).to be_within(120).of(expected[:start_ts])
    expect(stays.first[:end_ts]).to be_within(120).of(expected[:end_ts])
  end

  it 'resolves the home-gap scenario as one bridged home stay' do
    scenario = VisitScenarioGenerator.scenario(:home_gap, start_time: Time.zone.at(base_ts))
    reconciled, points = pre_pipeline(scenario)

    stays = assemble(reconciled, points)

    expect(stays.size).to eq(1)
    expected = scenario[:expected][:stays].first
    expect(stays.first[:start_ts]).to eq(expected[:start_ts])
    expect(stays.first[:end_ts]).to be_within(60).of(expected[:end_ts])
    expect(stays.first[:duration_s]).to be > 4.hours.to_i
  end
end
