# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::MovementReconciler do
  let(:policy) do
    Visits::Detection::Policy.new(
      stay_radius_m: 100, min_dwell_s: 300, min_points: 3, merge_gap_s: 900
    )
  end
  let(:base_ts) { 1_700_000_000 }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  def fragment(start_s, end_s, ids: [1, 2, 3])
    {
      point_ids: ids, start_ts: base_ts + start_s, end_ts: base_ts + end_s,
      center_lat: lat0, center_lon: lon0, count: ids.size, bridged_s: 0
    }
  end

  def seg(mode, start_s, end_s, confidence: 0.9, corrected: false)
    Visits::Detection::CandidateLoader::Seg.new(
      mode, confidence, corrected, base_ts + start_s, base_ts + end_s
    )
  end

  def reconcile(fragments, segments)
    described_class.new(policy).call(fragments, segments)
  end

  describe 'veto' do
    it 'drops a fragment mostly covered by a confident moving segment' do
      result = reconcile([fragment(0, 150)], [seg('driving', -600, 1800)])

      expect(result).to be_empty
    end

    it 'keeps a fragment inside an UNCERTAIN moving segment' do
      result = reconcile([fragment(0, 150)], [seg('driving', -600, 1800, confidence: 0.3)])

      expect(result.size).to eq(1)
    end

    it 'treats corrected segments as confident regardless of score' do
      result = reconcile([fragment(0, 150)], [seg('driving', -600, 1800, confidence: 0.1, corrected: true)])

      expect(result).to be_empty
    end

    it 'never vetoes on stationary or barely-overlapping segments' do
      fragments = [fragment(0, 3600)]
      segments = [seg('stationary', 0, 3600), seg('driving', 3000, 7200)]

      expect(reconcile(fragments, segments).size).to eq(1)
    end
  end

  describe 'boundary snapping' do
    it 'extends the start back to a moving segment that ended shortly before the first fix' do
      result = reconcile([fragment(480, 2000)], [seg('driving', -1200, 0)])

      expect(result.first[:start_ts]).to eq(base_ts)
    end

    it 'does not extend across more than snap_max_s of silence' do
      result = reconcile([fragment(1800, 3600)], [seg('driving', -1200, 0)])

      expect(result.first[:start_ts]).to eq(base_ts + 1800)
    end

    it 'trims the start forward when movement ended inside the fragment' do
      result = reconcile([fragment(0, 3600)], [seg('driving', -1200, 300)])

      expect(result.first[:start_ts]).to eq(base_ts + 300)
    end

    it 'extends the end forward to a moving segment that started shortly after the last fix' do
      result = reconcile([fragment(0, 1800)], [seg('walking', 2100, 3000)])

      expect(result.first[:end_ts]).to eq(base_ts + 2100)
    end

    it 'trims the end back when movement started inside the fragment' do
      result = reconcile([fragment(0, 3600)], [seg('driving', 3300, 7200)])

      expect(result.first[:end_ts]).to eq(base_ts + 3300)
    end

    it 'still trims the start when the overlap is exactly snap_max_s' do
      result = reconcile([fragment(0, 3600)], [seg('driving', -1200, 900)])

      expect(result.first[:start_ts]).to eq(base_ts + 900)
    end

    # A slow "walking" segment that runs 17 minutes into a stationary stop is
    # below the veto fraction, so the fragment survives — but its dwell time
    # must not be handed to the movement either.
    it 'keeps the start when movement overlaps it by more than snap_max_s' do
      result = reconcile([fragment(0, 3600)], [seg('walking', -600, 1020)])

      expect(result.size).to eq(1)
      expect(result.first[:start_ts]).to eq(base_ts)
      expect(result.first[:end_ts]).to eq(base_ts + 3600)
    end

    it 'keeps the end when movement overlaps it by more than snap_max_s' do
      result = reconcile([fragment(0, 3600)], [seg('walking', 2580, 5000)])

      expect(result.size).to eq(1)
      expect(result.first[:start_ts]).to eq(base_ts)
      expect(result.first[:end_ts]).to eq(base_ts + 3600)
    end

    it 'keeps a stay that a long overlap would have trimmed below the minimum dwell' do
      long_dwell = Visits::Detection::Policy.new(
        stay_radius_m: 100, min_dwell_s: 1800, min_points: 3, merge_gap_s: 900
      )
      points = [0, 1200, 2400].each_with_index.map do |at, i|
        Visits::Detection::CandidateLoader::Pt.new(i + 1, lat0, lon0, base_ts + at, 10)
      end

      reconciled = described_class.new(long_dwell).call([fragment(0, 2400)], [seg('walking', -600, 1020)])
      stays = Visits::Detection::StayAssembler.new(long_dwell).call(reconciled, points.index_by(&:id))

      expect(stays.size).to eq(1)
      expect(stays.first[:start_ts]).to eq(base_ts)
    end

    # A refused trim must not fall through to the extend, which would jump the
    # boundary back over the refused segment onto the one before it.
    it 'does not extend the start across a movement segment whose trim was refused' do
      segments = [seg('driving', -2000, -300), seg('walking', -300, 1020)]

      result = reconcile([fragment(0, 3600)], segments)

      expect(result.first[:start_ts]).to eq(base_ts)
    end

    it 'does not extend the end across a movement segment whose trim was refused' do
      segments = [seg('walking', 2580, 3900), seg('driving', 3900, 7000)]

      result = reconcile([fragment(0, 3600)], segments)

      expect(result.first[:end_ts]).to eq(base_ts + 3600)
    end
  end

  describe 'corroboration' do
    it 'flags fragments overlapped by a stationary segment' do
      corroborated = reconcile([fragment(0, 1800)], [seg('stationary', 0, 1800)]).first
      lonely = reconcile([fragment(0, 1800)], []).first

      expect(corroborated[:corroborated]).to be(true)
      expect(lonely[:corroborated]).to be(false)
    end
  end

  it 'resolves the cold-start scenario: stay starts when the drive ended' do
    scenario = VisitScenarioGenerator.scenario(:cold_start, start_time: Time.zone.at(base_ts))
    swept = Visits::Detection::DwellSweep.new(policy).call(as_detection_points(scenario[:points]))
    bridged = Visits::Detection::GapBridger.new(policy).call(swept)

    result = reconcile(bridged, as_detection_segments(scenario[:segments]))

    expected = scenario[:expected][:stays].first
    stay = result.max_by { |f| f[:count] }
    expect(stay[:start_ts]).to eq(expected[:start_ts])
    expect(stay[:end_ts]).to eq(expected[:end_ts])
  end

  it 'resolves the drive-carving scenario to nothing that could become a visit' do
    scenario = VisitScenarioGenerator.scenario(:drive_carving, start_time: Time.zone.at(base_ts))
    swept = Visits::Detection::DwellSweep.new(policy).call(as_detection_points(scenario[:points]))
    bridged = Visits::Detection::GapBridger.new(policy).call(swept)

    result = reconcile(bridged, as_detection_segments(scenario[:segments]))

    survivors = result.select do |f|
      (f[:end_ts] - f[:start_ts]) >= policy.min_dwell_s && f[:count] >= policy.min_points
    end
    expect(survivors).to be_empty
  end
end
