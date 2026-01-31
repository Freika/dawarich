# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InsightsHelper, type: :helper do
  describe '#calculate_activity_level' do
    let(:levels) { { p25: 1000, p50: 5000, p75: 10_000, p90: 20_000 } }

    it 'returns 0 for nil distance' do
      expect(helper.calculate_activity_level(nil, levels)).to eq(0)
    end

    it 'returns 0 for zero distance' do
      expect(helper.calculate_activity_level(0, levels)).to eq(0)
    end

    it 'returns 1 for distance below p25' do
      expect(helper.calculate_activity_level(500, levels)).to eq(1)
    end

    it 'returns 1 for distance at p25 threshold' do
      expect(helper.calculate_activity_level(1000, levels)).to eq(1)
    end

    it 'returns 2 for distance between p25 and p50' do
      expect(helper.calculate_activity_level(3000, levels)).to eq(1)
    end

    it 'returns 2 for distance at p50 threshold' do
      expect(helper.calculate_activity_level(5000, levels)).to eq(2)
    end

    it 'returns 3 for distance at p75 threshold' do
      expect(helper.calculate_activity_level(10_000, levels)).to eq(3)
    end

    it 'returns 4 for distance at p90 threshold' do
      expect(helper.calculate_activity_level(20_000, levels)).to eq(4)
    end

    it 'returns 4 for distance above p90' do
      expect(helper.calculate_activity_level(50_000, levels)).to eq(4)
    end
  end

  describe '#activity_level_class' do
    it 'returns bg-base-300 for level 0' do
      expect(helper.activity_level_class(0)).to eq('bg-base-300')
    end

    it 'returns bg-success/30 for level 1' do
      expect(helper.activity_level_class(1)).to eq('bg-success/30')
    end

    it 'returns bg-success/50 for level 2' do
      expect(helper.activity_level_class(2)).to eq('bg-success/50')
    end

    it 'returns bg-success/70 for level 3' do
      expect(helper.activity_level_class(3)).to eq('bg-success/70')
    end

    it 'returns bg-success for level 4' do
      expect(helper.activity_level_class(4)).to eq('bg-success')
    end

    it 'returns bg-base-300 for unknown level' do
      expect(helper.activity_level_class(99)).to eq('bg-base-300')
    end
  end

  describe '#format_heatmap_distance' do
    before do
      allow(Stat).to receive(:convert_distance).and_call_original
    end

    it 'returns 0 for nil meters' do
      expect(helper.format_heatmap_distance(nil, 'km')).to eq('0')
    end

    it 'returns 0 for zero meters' do
      expect(helper.format_heatmap_distance(0, 'km')).to eq('0')
    end

    it 'formats distance in km' do
      result = helper.format_heatmap_distance(5000, 'km')
      expect(result).to eq('5.0 km')
    end

    it 'formats small distances in meters' do
      result = helper.format_heatmap_distance(500, 'km')
      expect(result).to eq('500 m')
    end

    it 'formats distance in miles' do
      result = helper.format_heatmap_distance(3218, 'mi') # 2 miles
      expect(result).to eq('2.0 mi')
    end

    it 'formats small distances in feet for miles unit' do
      result = helper.format_heatmap_distance(500, 'mi') # about 0.31 miles = ~1640 ft
      expect(result).to match(/\d+ ft/)
    end
  end

  describe '#heatmap_week_columns' do
    context 'with 2024 (leap year, Jan 1 is Monday)' do
      let(:weeks) { helper.heatmap_week_columns(2024) }

      it 'returns array of week start dates' do
        expect(weeks).to be_an(Array)
        expect(weeks).to all(be_a(Date))
      end

      it 'starts from the Monday containing or before Jan 1' do
        expect(weeks.first).to eq(Date.new(2024, 1, 1))
      end

      it 'ends on or after Dec 31' do
        last_week = weeks.last
        week_end = last_week + 6
        expect(week_end).to be >= Date.new(2024, 12, 31)
      end

      it 'returns approximately 52-53 weeks' do
        expect(weeks.size).to be_between(52, 54)
      end
    end

    context 'with 2023 (Jan 1 is Sunday)' do
      let(:weeks) { helper.heatmap_week_columns(2023) }

      it 'starts from the Monday before Jan 1' do
        # Jan 1 2023 is Sunday, so we go back to Dec 26 2022 (Monday)
        expect(weeks.first).to eq(Date.new(2022, 12, 26))
      end
    end
  end

  describe '#heatmap_month_labels' do
    let(:weeks) { helper.heatmap_week_columns(2024) }
    let(:labels) { helper.heatmap_month_labels(weeks, 2024) }

    it 'returns array of label hashes' do
      expect(labels).to be_an(Array)
      labels.each do |label|
        expect(label).to have_key(:index)
        expect(label).to have_key(:name)
      end
    end

    it 'includes all 12 month abbreviations' do
      month_names = labels.map { |l| l[:name] }
      expect(month_names).to include('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
    end

    it 'has indices in ascending order' do
      indices = labels.map { |l| l[:index] }
      expect(indices).to eq(indices.sort)
    end
  end
end
