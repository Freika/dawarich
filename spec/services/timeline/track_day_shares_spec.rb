# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timeline::TrackDayShares do
  let(:tz) { 'Europe/Berlin' }

  def track_double(start_at:, end_at:)
    instance_double('Track', start_at: start_at, end_at: end_at)
  end

  def shares(start_at:, end_at:, timezone: tz)
    described_class.shares_for(track_double(start_at: start_at, end_at: end_at), timezone)
  end

  describe '.shares_for' do
    it 'returns a single full share for a track entirely within one local day' do
      result = shares(
        start_at: Time.zone.local(2026, 4, 27, 9, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 4, 27, 17, 0).in_time_zone(tz)
      )
      expect(result).to eq(Date.new(2026, 4, 27) => 1.0)
    end

    it 'falls back to the start day with full share when start_at == end_at' do
      moment = Time.zone.local(2026, 4, 27, 9, 0).in_time_zone(tz)
      result = shares(start_at: moment, end_at: moment)
      expect(result).to eq(Date.new(2026, 4, 27) => 1.0)
    end

    it 'falls back to the start day with full share when end_at precedes start_at' do
      result = shares(
        start_at: Time.zone.local(2026, 4, 27, 12, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 4, 27, 11, 0).in_time_zone(tz)
      )
      expect(result).to eq(Date.new(2026, 4, 27) => 1.0)
    end

    it 'splits an overnight track in proportion to time spent on each day' do
      result = shares(
        start_at: Time.zone.local(2026, 4, 27, 23, 30).in_time_zone(tz),
        end_at: Time.zone.local(2026, 4, 28, 2, 0).in_time_zone(tz)
      )
      expect(result.keys).to eq([Date.new(2026, 4, 27), Date.new(2026, 4, 28)])
      # 30 min on Apr 27, 120 min on Apr 28 → 1:4 ratio
      expect(result[Date.new(2026, 4, 27)]).to be_within(0.001).of(0.2)
      expect(result[Date.new(2026, 4, 28)]).to be_within(0.001).of(0.8)
      expect(result.values.sum).to be_within(0.0001).of(1.0)
    end

    it 'distributes a multi-day track across every day it touches' do
      result = shares(
        start_at: Time.zone.local(2026, 4, 27, 18, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 4, 30, 6, 0).in_time_zone(tz)
      )
      expect(result.keys).to eq([
                                  Date.new(2026, 4, 27),
                                  Date.new(2026, 4, 28),
                                  Date.new(2026, 4, 29),
                                  Date.new(2026, 4, 30)
                                ])
      expect(result.values.sum).to be_within(0.0001).of(1.0)
    end

    it 'handles a cross-month boundary' do
      result = shares(
        start_at: Time.zone.local(2026, 3, 31, 23, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 4, 1, 1, 0).in_time_zone(tz)
      )
      expect(result.keys).to eq([Date.new(2026, 3, 31), Date.new(2026, 4, 1)])
      expect(result.values.sum).to be_within(0.0001).of(1.0)
    end

    it 'balances correctly across the spring-forward DST boundary in Europe/Berlin' do
      # 2026-03-29 02:00 Berlin → 03:00 (no 02:30 exists)
      result = shares(
        start_at: Time.zone.local(2026, 3, 28, 22, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 3, 29, 5, 0).in_time_zone(tz)
      )
      expect(result.keys).to eq([Date.new(2026, 3, 28), Date.new(2026, 3, 29)])
      expect(result.values.sum).to be_within(0.0001).of(1.0)
    end

    it 'balances correctly across the fall-back DST boundary in Europe/Berlin' do
      # 2026-10-25 03:00 Berlin → 02:00 (the 02:00-03:00 hour repeats)
      result = shares(
        start_at: Time.zone.local(2026, 10, 24, 22, 0).in_time_zone(tz),
        end_at: Time.zone.local(2026, 10, 25, 5, 0).in_time_zone(tz)
      )
      expect(result.keys).to eq([Date.new(2026, 10, 24), Date.new(2026, 10, 25)])
      expect(result.values.sum).to be_within(0.0001).of(1.0)
    end

    it 'defaults to UTC when timezone is nil' do
      utc_result = shares(
        start_at: Time.utc(2026, 4, 27, 23, 30),
        end_at: Time.utc(2026, 4, 28, 0, 30),
        timezone: nil
      )
      expect(utc_result.keys).to eq([Date.new(2026, 4, 27), Date.new(2026, 4, 28)])
    end
  end
end
