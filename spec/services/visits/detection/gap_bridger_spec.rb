# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::GapBridger do
  let(:policy) do
    Visits::Detection::Policy.new(
      stay_radius_m: 100, min_dwell_s: 300, min_points: 3, merge_gap_s: 900
    )
  end
  let(:base_ts) { 1_700_000_000 }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  def east(meters) = meters / (111_320.0 * Math.cos(lat0 * Math::PI / 180))

  def fragment(ids, start_s, end_s, deast: 0.0)
    {
      point_ids: ids,
      start_ts: base_ts + start_s,
      end_ts: base_ts + end_s,
      center_lat: lat0,
      center_lon: lon0 + east(deast),
      count: ids.size
    }
  end

  def bridge(fragments)
    described_class.new(policy).call(fragments)
  end

  it 'bridges a long same-place silence into one fragment and records the bridged time' do
    result = bridge([fragment([1, 2, 3], 0, 1200), fragment([4, 5], 1200 + (4 * 3600), 1200 + (4 * 3600) + 600)])

    expect(result[:untracked]).to be_empty
    expect(result[:fragments].size).to eq(1)

    merged = result[:fragments].first
    expect(merged[:point_ids]).to eq([1, 2, 3, 4, 5])
    expect(merged[:end_ts] - merged[:start_ts]).to eq(1200 + (4 * 3600) + 600)
    expect(merged[:bridged_s]).to eq(4 * 3600)
  end

  it 'does not count sub-sweep-gap radius blips as bridged silence' do
    result = bridge([fragment([1, 2], 0, 600), fragment([3, 4], 900, 1500)])

    expect(result[:fragments].size).to eq(1)
    expect(result[:fragments].first[:bridged_s]).to eq(0)
  end

  it 'refuses to bridge beyond the cap and emits an untracked interval instead' do
    eight_days = 8 * 24 * 3600
    result = bridge([fragment([1, 2, 3], 0, 1200), fragment([4, 5, 6], eight_days, eight_days + 1200)])

    expect(result[:fragments].size).to eq(2)
    expect(result[:untracked].size).to eq(1)
    expect(result[:untracked].first[:start_ts]).to eq(base_ts + 1200)
    expect(result[:untracked].first[:end_ts]).to eq(base_ts + eight_days)
  end

  it 'emits an untracked interval for a displaced gap and keeps the fragments apart' do
    result = bridge([fragment([1, 2, 3], 0, 1200),
                     fragment([4, 5], 1200 + (79 * 60), 1200 + (79 * 60) + 900, deast: 700.0)])

    expect(result[:fragments].size).to eq(2)
    expect(result[:untracked]).to eq(
      [{ start_ts: base_ts + 1200, end_ts: base_ts + 1200 + (79 * 60), last_fix: { lat: lat0, lon: lon0 } }]
    )
  end

  it 'stays silent about short displaced gaps' do
    result = bridge([fragment([1], 0, 300), fragment([2], 600, 900, deast: 500.0)])

    expect(result[:fragments].size).to eq(2)
    expect(result[:untracked]).to be_empty
  end

  it 'chain-bridges through a lone same-place fix inside the silence' do
    result = bridge(
      [
        fragment([1, 2, 3], 0, 1200),
        fragment([4], 1200 + (2 * 3600), 1200 + (2 * 3600)),
        fragment([5, 6], 1200 + (4 * 3600), 1200 + (4 * 3600) + 600)
      ]
    )

    expect(result[:fragments].size).to eq(1)
    expect(result[:fragments].first[:point_ids]).to eq([1, 2, 3, 4, 5, 6])
  end

  it 'breaks the bridge on a mid-silence fix somewhere else' do
    result = bridge(
      [
        fragment([1, 2, 3], 0, 1200),
        fragment([4], 1200 + (2 * 3600), 1200 + (2 * 3600), deast: 900.0),
        fragment([5, 6], 1200 + (4 * 3600), 1200 + (4 * 3600) + 600)
      ]
    )

    expect(result[:fragments].size).to eq(3)
    expect(result[:untracked].size).to eq(2)
  end

  it 'resolves the home-gap scenario to one bridged home fragment' do
    scenario = VisitScenarioGenerator.scenario(:home_gap, start_time: Time.zone.at(base_ts))
    sweep = Visits::Detection::DwellSweep.new(policy).call(as_detection_points(scenario[:points]))

    result = bridge(sweep)

    expect(result[:untracked]).to be_empty
    home = result[:fragments].max_by { |f| f[:count] }
    expected = scenario[:expected][:stays].first
    expect(home[:start_ts]).to eq(expected[:start_ts])
    expect(home[:end_ts]).to be >= expected[:end_ts]
    expect(home[:bridged_s]).to be >= 3.5 * 3600
  end

  it 'resolves the dark-dinner scenario to a stay plus an untracked interval' do
    scenario = VisitScenarioGenerator.scenario(:dark_dinner, start_time: Time.zone.at(base_ts))
    sweep = Visits::Detection::DwellSweep.new(policy).call(as_detection_points(scenario[:points]))

    result = bridge(sweep)

    expected_untracked = scenario[:expected][:untracked].first
    expect(result[:untracked].size).to eq(1)
    expect(result[:untracked].first[:start_ts]).to eq(expected_untracked[:start_ts])
    expect(result[:untracked].first[:end_ts]).to eq(expected_untracked[:end_ts])
  end
end
