# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::TileEpoch do
  let(:user_id) { create(:user).id }

  def component(start_time, end_time)
    described_class.etag_component(user_id, start_time.to_i, end_time.to_i)
  end

  describe '.etag_component' do
    it 'is stable across repeated reads for an untouched user' do
      first = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))
      second = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))

      expect(first).to eq(second)
    end

    it 'changes for ranges covering a bumped year and stays for ranges excluding it' do
      covering_before = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))
      excluding_before = component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))

      described_class.bump(user_id, timestamps: [Time.utc(2024, 6, 1).to_i])

      expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).not_to eq(covering_before)
      expect(component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))).to eq(excluding_before)
    end

    it 'derives the year in UTC on both sides of a year boundary' do
      before_2025 = component(Time.utc(2025, 1, 1), Time.utc(2025, 12, 31))
      before_2026 = component(Time.utc(2026, 1, 1), Time.utc(2026, 12, 31))

      described_class.bump(user_id, timestamps: [Time.utc(2025, 12, 31, 23, 59, 59).to_i])

      expect(component(Time.utc(2025, 1, 1), Time.utc(2025, 12, 31))).not_to eq(before_2025)
      expect(component(Time.utc(2026, 1, 1), Time.utc(2026, 12, 31))).to eq(before_2026)
    end

    it 'reseeds a never-before-issued token after eviction' do
      original = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))

      Rails.cache.delete("#{Points::TileEpoch::KEY_PREFIX}:#{user_id}:2024")

      expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).not_to eq(original)
    end
  end

  describe '.bump_range' do
    it 'bumps interior years of a multi-year window, not just the endpoints' do
      before_middle = component(Time.utc(2022, 1, 1), Time.utc(2022, 12, 31))

      described_class.bump_range(user_id, Time.utc(2021, 6, 1).to_i, Time.utc(2023, 6, 1).to_i)

      expect(component(Time.utc(2022, 1, 1), Time.utc(2022, 12, 31))).not_to eq(before_middle)
    end
  end

  describe '.bump_range with a degenerate window' do
    it 'fails closed via the sentinel instead of silently skipping the bump' do
      before_value = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))

      described_class.bump_range(user_id, Time.utc(2023, 1, 1).to_i, Time.utc(2021, 1, 1).to_i)

      expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).not_to eq(before_value)
    end
  end

  describe 'failure isolation' do
    it 'never raises out of bump when the cache write fails' do
      allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError)

      expect { described_class.bump(user_id, timestamps: [Time.utc(2024, 6, 1).to_i]) }
        .not_to raise_error
    end
  end

  describe '.bump without timestamps' do
    it 'falls back to the sentinel and invalidates every range' do
      range_a = component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))
      range_b = component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))

      described_class.bump(user_id)

      expect(component(Time.utc(2019, 1, 1), Time.utc(2019, 12, 31))).not_to eq(range_a)
      expect(component(Time.utc(2024, 1, 1), Time.utc(2024, 12, 31))).not_to eq(range_b)
    end
  end
end
