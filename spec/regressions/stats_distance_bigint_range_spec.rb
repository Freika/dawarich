# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats distance accepts values beyond 4-byte integer range' do
  let(:user)            { create(:user) }
  let(:int4_max)        { 2_147_483_647 }
  let(:overflow_meters) { 12_089_677_383 }

  describe 'persistence at the column level' do
    it 'stores a value just above the int4 maximum' do
      stat = build(:stat, user: user, year: 2026, month: 1, distance: int4_max + 1)

      expect { stat.save! }.not_to raise_error
      expect(stat.reload.distance).to eq(int4_max + 1)
    end

    it 'stores the overflow value reported in the wild' do
      stat = build(:stat, user: user, year: 2026, month: 2, distance: overflow_meters)

      expect { stat.save! }.not_to raise_error
      expect(stat.reload.distance).to eq(overflow_meters)
    end
  end

  describe 'Stats::CalculateMonth with an overflowing monthly distance' do
    let(:year)  { 2026 }
    let(:month) { 3 }
    let(:overflowing_daily_distance) { (1..31).map { |d| [d, (overflow_meters / 31) + 1] } }

    before do
      create(:point, user: user, timestamp: DateTime.new(year, month, 1).to_i + 3600)
      allow_any_instance_of(Stat).to receive(:distance_by_day).and_return(overflowing_daily_distance)
      allow_any_instance_of(Stats::HexagonCalculator).to receive(:call).and_return({})
      allow_any_instance_of(CountriesAndCities).to receive(:call).and_return([])
    end

    it 'persists the bigint distance and does not enqueue a failure notification' do
      expect do
        Stats::CalculateMonth.new(user.id, year, month).call
      end.not_to(change { user.notifications.where(title: 'Stats update failed').count })

      stat = Stat.find_by!(user: user, year: year, month: month)
      expect(stat.distance).to be > int4_max
    end
  end
end
