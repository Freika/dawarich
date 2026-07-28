# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::StayPointDetector do
  let(:user)    { create(:user) }
  let(:base_ts) { 1_700_000_000 }
  let(:lat0)    { 52.5 }
  let(:lon0)    { 13.4 }

  # Offsets in meters (north for lat, east for lon) at ~52.5°N.
  def north(meters) = meters / 111_000.0
  def east(meters)  = meters / (111_000.0 * Math.cos(lat0 * Math::PI / 180))

  def make_point(at:, dnorth: 0.0, deast: 0.0, accuracy: 10)
    lat = lat0 + north(dnorth)
    lon = lon0 + east(deast)
    create(:point, user: user, latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})",
                   timestamp: at, accuracy: accuracy, visit_id: nil)
  end

  def detect(from: base_ts - 1, to: base_ts + 100_000)
    described_class.new(user, start_at: from, end_at: to).call
  end

  # Defaults: radius 100 m, min_dwell 300 s, min_points 3, max_gap 3600 s, merge_gap 900 s, drift_cap 1.5.

  describe '#call' do
    it 'ignores points at exactly (0,0)' do
      6.times do |i|
        create(:point, user: user, latitude: 0.0, longitude: 0.0,
                       lonlat: 'POINT(0.0 0.0)', timestamp: base_ts + (i * 120),
                       accuracy: 10, visit_id: nil)
      end

      expect(detect).to be_empty
    end

    it '(a) groups a tight stationary cluster into one visit' do
      6.times { |i| make_point(at: base_ts + i * 120, dnorth: (i.even? ? 5 : -5)) }

      clusters = detect

      expect(clusters.size).to eq(1)
      expect(clusters.first[:point_count]).to eq(6)
    end

    it '(b) produces no visit for a straight-line drive' do
      6.times { |i| make_point(at: base_ts + i * 60, dnorth: i * 220) }

      expect(detect).to be_empty
    end

    it '(c) keeps a leave-and-return separated by more than the merge gap as two visits' do
      4.times { |i| make_point(at: base_ts + i * 120, dnorth: 5) }      # cluster A (t .. +360)
      make_point(at: base_ts + 1700, dnorth: 400)                       # away
      4.times { |i| make_point(at: base_ts + 1800 + i * 120, dnorth: 5) } # cluster C (t+1800 ..)

      expect(detect.size).to eq(2)
    end

    it '(d) merges a leave-and-return within the merge gap into one visit' do
      4.times { |i| make_point(at: base_ts + i * 120, dnorth: 5) }      # cluster A (.. +360)
      make_point(at: base_ts + 460, dnorth: 400)                        # brief away
      4.times { |i| make_point(at: base_ts + 560 + i * 120, dnorth: 5) } # back (gap from A.end = 200 s)

      clusters = detect

      expect(clusters.size).to eq(1)
      merged = clusters.first
      # Step 7 merge must update all three of: point_count, point_ids, end_time.
      expect(merged[:point_count]).to eq(8)
      expect(merged[:point_ids].size).to eq(8)
      expect(merged[:end_time]).to eq(base_ts + 560 + 3 * 120) # last point of the returned cluster
    end

    it '(e) splits visits across a gap longer than max_gap at the same place' do
      [0, 150, 300].each { |t| make_point(at: base_ts + t, dnorth: 5) }
      [7200, 7350, 7500].each { |t| make_point(at: base_ts + t, dnorth: -5) } # +2h, same spot

      clusters = detect

      expect(clusters.size).to eq(2)
      expect(clusters.map { |cluster| cluster[:point_count] }).to eq([3, 3])
      expect(clusters.first[:end_time]).to eq(base_ts + 300)
      expect(clusters.last[:start_time]).to eq(base_ts + 7200)
    end

    it 'does not merge same-place stays back together when their gap exceeds max_gap' do
      user.update!(
        settings: user.settings.merge('stay_max_gap_minutes' => 5, 'merge_threshold_minutes' => 15)
      )
      [0, 150, 300].each { |t| make_point(at: base_ts + t, dnorth: 5) }
      [900, 1050, 1200].each { |t| make_point(at: base_ts + t, dnorth: -5) }

      expect(detect.size).to eq(2)
    end

    it '(f) splits into two visits across a long gap at different places' do
      4.times { |i| make_point(at: base_ts + i * 120, dnorth: 5) }            # place 1
      4.times { |i| make_point(at: base_ts + 7200 + i * 120, dnorth: 300) }   # +2h, place 2 (300 m away)

      expect(detect.size).to eq(2)
    end

    it '(g) drops a stop shorter than the minimum dwell' do
      [0, 60, 120].each { |t| make_point(at: base_ts + t, dnorth: 5) } # 120 s < 300 s

      expect(detect).to be_empty
    end

    it '(h) keeps a fast walk-around that stays within the radius (no speed gate)' do
      # Alternates ~89 m every 60 s => ~1.5 m/s, but never leaves the 100 m radius.
      6.times { |i| make_point(at: base_ts + i * 60, dnorth: (i.even? ? 0 : 89)) }

      clusters = detect

      expect(clusters.size).to eq(1)
      expect(clusters.first[:point_count]).to eq(6)
    end

    it '(i) splits a slow continuous drift instead of forming one blob' do
      10.times { |i| make_point(at: base_ts + i * 120, dnorth: i * 67) } # marches ~67 m each step

      max_points = detect.map { |c| c[:point_count] }.max.to_i
      expect(max_points).to be < 10
    end

    it '(k) seeds the new stay with the departing point so consecutive brief stays are not lost' do
      [0, 150, 300].each { |t| make_point(at: base_ts + t, dnorth: 5) }        # stay A (loc1)
      [450, 600, 750].each { |t| make_point(at: base_ts + t, dnorth: 400) }    # stay B (loc2)

      # B only reaches min_points (3) because its first point — the one that departed A — seeds it.
      expect(detect.size).to eq(2)
    end

    it '(m) starts a new stay after max_gap even when the later points remain near the previous anchor' do
      [0, 150, 300].each { |t| make_point(at: base_ts + t, dnorth: 0) }
      [7200, 7320, 7440, 7560].each_with_index { |t, i| make_point(at: base_ts + t, dnorth: 20 + (i * 20)) }

      clusters = detect

      expect(clusters.size).to eq(2)
      expect(clusters.first[:end_time]).to eq(base_ts + 300)
      expect(clusters.last[:start_time]).to eq(base_ts + 7200)
    end

    it 'returns the DbscanClusterer cluster-hash shape with positive real point ids' do
      ids = 4.times.map { |i| make_point(at: base_ts + i * 120, dnorth: 5).id }

      cluster = detect.first

      expect(cluster.keys).to match_array(%i[visit_id point_ids start_time end_time point_count])
      expect(cluster[:point_ids]).to match_array(ids)
      expect(cluster[:point_ids]).to all(be_positive)
      expect(cluster[:start_time]).to eq(base_ts)
    end

    it 'returns [] and logs a skip when over the candidate cap' do
      make_point(at: base_ts, dnorth: 5)
      stub_const("#{described_class}::MAX_CANDIDATE_POINTS", 0)

      expect(Rails.logger).to receive(:warn).with(/StayPointDetector skip/)
      expect(detect).to eq([])
    end
  end
end
