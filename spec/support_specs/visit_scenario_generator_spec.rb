# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitScenarioGenerator do
  scenario_names = %i[home_gap dark_dinner drive_carving reentry cold_start day_boundary batch_boundary
                      dark_venue]

  let(:start_time) { Time.zone.parse('2026-01-05 09:00:00 UTC') }

  def scenario(name)
    described_class.scenario(name, start_time: start_time, seed: 42)
  end

  it 'exposes exactly the documented scenarios' do
    expect(described_class::SCENARIOS.keys)
      .to match_array(%i[home_gap dark_dinner drive_carving reentry cold_start day_boundary batch_boundary
                         dark_venue])
  end

  scenario_names.each do |name|
    context "#{name} (shared invariants)" do
      let(:result) { scenario(name) }

      it 'is deterministic for the same seed' do
        expect(described_class.scenario(name, start_time: start_time, seed: 42)).to eq(result)
      end

      it 'produces strictly increasing point timestamps near Leipzig' do
        timestamps = result[:points].map { |p| p[:timestamp] }
        expect(timestamps).to eq(timestamps.sort)
        expect(timestamps.uniq.size).to eq(timestamps.size)

        result[:points].each do |p|
          expect(p[:lat]).to be_within(0.1).of(51.3402)
          expect(p[:lon]).to be_within(0.15).of(12.3712)
          expect(p[:accuracy]).to be_positive
          expect(p[:velocity]).to be >= 0
        end
      end

      it 'produces ordered, non-overlapping expected intervals' do
        intervals = (result[:expected][:stays] + result[:expected][:untracked])
                    .map { |i| [i[:start_ts], i[:end_ts]] }
                    .sort_by(&:first)

        intervals.each { |s, e| expect(e).to be > s }
        intervals.each_cons(2) { |(_, e1), (s2, _)| expect(s2).to be >= e1 }
      end

      it 'produces ordered segments with known modes' do
        result[:segments].each do |seg|
          expect(%w[stationary walking running cycling driving train flying]).to include(seg[:mode])
          expect(seg[:end_ts]).to be > seg[:start_ts]
          expect(seg[:confidence_score]).to be_between(0.0, 1.0)
        end
        starts = result[:segments].map { |s| s[:start_ts] }
        expect(starts).to eq(starts.sort)
      end
    end
  end

  describe ':home_gap' do
    let(:result) { scenario(:home_gap) }

    it 'expects one stay bridging the 4h silence at home' do
      expect(result[:expected][:untracked]).to be_empty
      expect(result[:expected][:stays].size).to eq(1)

      stay = result[:expected][:stays].first
      expect(stay[:end_ts] - stay[:start_ts]).to be > 4.hours.to_i

      gaps = result[:points].each_cons(2).map { |a, b| b[:timestamp] - a[:timestamp] }
      expect(gaps.max).to be > 3.5.hours.to_i
    end
  end

  describe ':dark_dinner' do
    let(:result) { scenario(:dark_dinner) }

    it 'expects a stay, then an untracked interval, and nothing at the resume location' do
      expect(result[:expected][:stays].size).to eq(1)
      expect(result[:expected][:untracked].size).to eq(1)

      stay = result[:expected][:stays].first
      untracked = result[:expected][:untracked].first
      expect(untracked[:start_ts]).to eq(stay[:end_ts])
      expect(untracked[:end_ts] - untracked[:start_ts]).to be_between(70.minutes.to_i, 90.minutes.to_i)

      resume_point = result[:points].find { |p| p[:timestamp] >= untracked[:end_ts] }
      dist_deg = Math.sqrt(((resume_point[:lat] - stay[:lat]) * 111_320)**2 +
                           ((resume_point[:lon] - stay[:lon]) * 69_600)**2)
      expect(dist_deg).to be > 400 # resumes far from the stay — displaced gap
    end
  end

  describe ':drive_carving' do
    it 'expects zero stays despite multi-minute traffic stops' do
      result = scenario(:drive_carving)
      expect(result[:expected][:stays]).to be_empty
      expect(result[:expected][:untracked]).to be_empty

      stop_gaps = result[:points].each_cons(2).count { |a, b| (b[:timestamp] - a[:timestamp]) > 60 }
      expect(stop_gaps).to eq(0) # continuous recording — stops are slow points, not gaps
    end
  end

  describe ':reentry' do
    it 'expects one merged stay covering the brief walk-away' do
      result = scenario(:reentry)
      expect(result[:expected][:stays].size).to eq(1)

      stay = result[:expected][:stays].first
      expect(stay[:end_ts] - stay[:start_ts]).to be_between(45.minutes.to_i, 60.minutes.to_i)
    end
  end

  describe ':cold_start' do
    it 'expects the stay start snapped to the driving segment end' do
      result = scenario(:cold_start)
      expect(result[:expected][:stays].size).to eq(1)

      driving = result[:segments].find { |s| s[:mode] == 'driving' }
      expect(result[:expected][:stays].first[:start_ts]).to eq(driving[:end_ts])
    end
  end

  describe ':day_boundary' do
    it 'expects one stay when started near midnight' do
      near_midnight = Time.zone.parse('2026-01-05 23:00:00 UTC')
      result = described_class.scenario(:day_boundary, start_time: near_midnight, seed: 42)
      expect(result[:expected][:stays].size).to eq(1)
      expect(result[:expected][:stays].first[:end_ts] - near_midnight.to_i).to be > 2.hours.to_i
    end
  end
end
