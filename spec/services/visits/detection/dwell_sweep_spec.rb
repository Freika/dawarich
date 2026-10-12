# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::DwellSweep do
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
      id, lat0 + north(dnorth), lon0 + east(deast), at, accuracy
    )
  end

  def sweep(points)
    described_class.new(policy).call(points)
  end

  it 'groups a tight stationary cluster into one fragment with a mean center' do
    points = 6.times.map { |i| pt(i + 1, at: base_ts + (i * 60), dnorth: (i % 2) * 10.0) }

    fragments = sweep(points)

    expect(fragments.size).to eq(1)
    fragment = fragments.first
    expect(fragment[:point_ids]).to eq((1..6).to_a)
    expect(fragment[:start_ts]).to eq(base_ts)
    expect(fragment[:end_ts]).to eq(base_ts + 300)
    expect(fragment[:center_lat]).to be_within(0.0002).of(lat0)
  end

  it 'emits fragments BELOW min dwell and min points — filtering is not its job' do
    points = [pt(1, at: base_ts), pt(2, at: base_ts + 60)]

    fragments = sweep(points)

    expect(fragments.size).to eq(1)
    expect(fragments.first[:point_ids]).to eq([1, 2])
    expect(fragments.first[:end_ts] - fragments.first[:start_ts]).to be < policy.min_dwell_s
  end

  it 'splits when the silence exceeds the sweep gap, even at the same spot' do
    early = 3.times.map { |i| pt(i + 1, at: base_ts + (i * 60)) }
    late  = 3.times.map { |i| pt(i + 4, at: base_ts + policy.sweep_gap_s + 300 + (i * 60)) }

    fragments = sweep(early + late)

    expect(fragments.size).to eq(2)
    expect(fragments.first[:point_ids]).to eq([1, 2, 3])
    expect(fragments.last[:point_ids]).to eq([4, 5, 6])
  end

  it 'splits when a point leaves the stay radius' do
    stay = 4.times.map { |i| pt(i + 1, at: base_ts + (i * 60)) }
    away = pt(5, at: base_ts + 240, deast: 400.0)

    fragments = sweep(stay + [away])

    expect(fragments.size).to eq(2)
    expect(fragments.first[:point_ids]).to eq([1, 2, 3, 4])
    expect(fragments.last[:point_ids]).to eq([5])
  end

  it 'caps drift from the first member so a slow drag cannot blob' do
    # Each step 60 m east: always within 100 m of the running mean, but the
    # fourth point crosses 150 m (1.5 × radius) from the first member.
    points = 5.times.map { |i| pt(i + 1, at: base_ts + (i * 60), deast: i * 60.0) }

    fragments = sweep(points)

    expect(fragments.size).to be > 1
    expect(fragments.first[:point_ids].size).to be < 5
  end

  it 'produces only sub-dwell fragments for a stop-and-go city drive' do
    scenario = VisitScenarioGenerator.scenario(:drive_carving, start_time: Time.zone.at(base_ts))
    fragments = sweep(as_detection_points(scenario[:points]))

    expect(fragments).to all(satisfy { |f| (f[:end_ts] - f[:start_ts]) < policy.min_dwell_s })
  end

  it 'returns fragments ordered by start time and handles empty input' do
    points = [pt(1, at: base_ts), pt(2, at: base_ts + 5000, deast: 500.0)]

    fragments = sweep(points)

    expect(fragments.map { |f| f[:start_ts] }).to eq(fragments.map { |f| f[:start_ts] }.sort)
    expect(sweep([])).to eq([])
  end
end
