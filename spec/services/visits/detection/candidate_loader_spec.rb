# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::CandidateLoader do
  let(:user) { create(:user) }
  let(:policy) { Visits::Detection::Policy.for(user) }
  let(:base_ts) { 1_700_000_000 }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  def make_point(at:, lat: nil, lon: nil, visit_id: nil, anomaly: nil, owner: user)
    lat ||= lat0
    lon ||= lon0
    create(:point, user: owner, latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})",
                   timestamp: at, accuracy: 10, visit_id: visit_id, anomaly: anomaly)
  end

  def load(from: base_ts, to: base_ts + 3600)
    described_class.new(user, start_at: from, end_at: to, policy: policy).call
  end

  describe '#call points' do
    it 'includes points already owned by a visit — detection is stateless over raw points' do
      visit = create(:visit, user: user)
      owned = make_point(at: base_ts + 10, visit_id: visit.id)
      free = make_point(at: base_ts + 20)

      result = load

      expect(result[:skipped]).to be(false)
      expect(result[:points].map(&:id)).to contain_exactly(owned.id, free.id)
    end

    it 'excludes anomalies, Null Island, other users and out-of-window points' do
      kept = make_point(at: base_ts + 10)
      make_point(at: base_ts + 20, anomaly: true)
      make_point(at: base_ts + 30, lat: 0.0, lon: 0.0)
      make_point(at: base_ts + 40, owner: create(:user))
      make_point(at: base_ts + 7200)

      expect(load[:points].map(&:id)).to eq([kept.id])
    end

    it 'returns timestamp-ordered structs with coordinates' do
      make_point(at: base_ts + 100)
      make_point(at: base_ts + 50)

      points = load[:points]

      expect(points.map(&:timestamp)).to eq(points.map(&:timestamp).sort)
      expect(points.first.lat).to be_within(0.0001).of(lat0)
      expect(points.first.lon).to be_within(0.0001).of(lon0)
      expect(points.first.accuracy).to eq(10)
    end

    it 'returns the skipped sentinel above the candidate cap' do
      stub_const('Visits::Detection::CandidateLoader::MAX_CANDIDATE_POINTS', 2)
      3.times { |i| make_point(at: base_ts + (i * 10)) }

      result = load

      expect(result[:skipped]).to be(true)
      expect(result[:points]).to be_empty
    end
  end

  describe '#call segments' do
    let(:track) { create(:track, user: user) }

    def make_segment(from_s, to_s, mode: :driving, track_row: track, **attrs)
      create(:track_segment, track: track_row, transportation_mode: mode,
                             start_at: Time.zone.at(base_ts + from_s),
                             end_at: Time.zone.at(base_ts + to_s), **attrs)
    end

    it 'loads window-overlapping segments with mode, confidence and corrected flag' do
      make_segment(100, 500, confidence_score: 0.85)
      make_segment(-500, 100, mode: :stationary, corrected_at: Time.zone.at(base_ts))
      make_segment(4000, 5000)
      other_track = create(:track, user: create(:user))
      make_segment(100, 500, track_row: other_track)

      segments = load[:segments]

      expect(segments.size).to eq(2)
      expect(segments.map(&:mode)).to contain_exactly('driving', 'stationary')
      expect(segments.map(&:start_ts)).to eq(segments.map(&:start_ts).sort)

      driving = segments.find { |s| s.mode == 'driving' }
      expect(driving.confidence).to eq(0.85)
      expect(driving.corrected).to be(false)

      stationary = segments.find { |s| s.mode == 'stationary' }
      expect(stationary.corrected).to be(true)
    end

    it 'ignores legacy segments without time anchors' do
      create(:track_segment, track: track, start_at: nil, end_at: nil)

      expect(load[:segments]).to be_empty
    end
  end
end
