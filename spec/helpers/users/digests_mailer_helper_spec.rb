# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DigestsMailerHelper, type: :helper do
  describe '#ascii_hbar' do
    it 'renders proportional bars for each value' do
      output = helper.ascii_hbar([50, 25, 0], labels: %w[A B C], width: 10, suffix: ' km')
      lines = output.split("\n")
      expect(lines.size).to eq 3
      expect(lines[0]).to include('A')
      expect(lines[0]).to match(/█{10}.*50 km/)
      expect(lines[1]).to match(/█{5}.*25 km/)
      expect(lines[2]).to include('C').and include('0 km')
    end

    it 'handles an empty input' do
      expect(helper.ascii_hbar([], labels: [])).to eq ''
    end

    it 'handles all-equal values' do
      output = helper.ascii_hbar([10, 10], labels: %w[X Y], width: 8)
      lines = output.split("\n")
      expect(lines[0]).to match(/█{8}/)
      expect(lines[1]).to match(/█{8}/)
    end
  end

  describe '#ascii_sparkline' do
    it 'maps values to 8 block characters proportionally' do
      output = helper.ascii_sparkline([0, 1, 2, 3, 4, 5, 6, 7])
      expect(output.chars).to eq %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █]
    end

    it 'handles all-equal values by rendering full blocks' do
      expect(helper.ascii_sparkline([5, 5, 5])).to eq '███'
    end

    it 'handles an empty array' do
      expect(helper.ascii_sparkline([])).to eq ''
    end
  end

  describe '#ascii_year_heatmap' do
    let(:start_date) { Date.new(2025, 1, 1) }

    it 'returns 7 lines (one per weekday) spanning 52–53 weeks' do
      daily = (0...365).each_with_object({}) { |i, h| h[start_date + i] = i.to_f }
      output = helper.ascii_year_heatmap(daily, start_date: start_date)
      lines = output.split("\n")
      expect(lines.size).to eq 7
      expect(lines.first.length).to be >= 52
      expect(lines.first.length).to be <= 53
    end

    it 'uses · for zero-distance days and higher levels for larger quartiles' do
      daily = { start_date => 0, (start_date + 1) => 10, (start_date + 2) => 1000 }
      output = helper.ascii_year_heatmap(daily, start_date: start_date)
      expect(output).to include('·')
      expect(output).to include('█')
    end

    it 'handles a leap year (366 days)' do
      leap_start = Date.new(2024, 1, 1)
      daily = (0...366).each_with_object({}) { |i, h| h[leap_start + i] = 5.0 }
      output = helper.ascii_year_heatmap(daily, start_date: leap_start)
      expect(output.split("\n").size).to eq 7
    end
  end

  describe '#ascii_trend' do
    it 'renders an upward trend with percentage' do
      expect(helper.ascii_trend(120, 100)).to eq '↑ +20%'
    end

    it 'renders a downward trend' do
      expect(helper.ascii_trend(80, 100)).to eq '↓ -20%'
    end

    it 'renders "same" when values are equal' do
      expect(helper.ascii_trend(50, 50)).to eq '→ same'
    end

    it 'guards against division by zero' do
      expect(helper.ascii_trend(10, 0)).to eq '↑ new'
      expect(helper.ascii_trend(0, 0)).to eq '→ same'
    end
  end

  describe '#ascii_ranked_list' do
    it 'sorts by value descending, bars proportional to the top' do
      items = [
        { 'name' => 'A', 'minutes' => 100 },
        { 'name' => 'B', 'minutes' => 50 },
        { 'name' => 'C', 'minutes' => 25 }
      ]
      output = helper.ascii_ranked_list(items, value_key: 'minutes', label_key: 'name',
                                        width: 20, format: ->(v) { "#{v}m" })
      lines = output.split("\n")
      expect(lines[0]).to start_with('1. A')
      expect(lines[0]).to match(/█{20}.*100m/)
      expect(lines[1]).to match(/█{10}.*50m/)
      expect(lines[2]).to match(/█{5}.*25m/)
    end

    it 'handles empty input' do
      expect(helper.ascii_ranked_list([], value_key: 'minutes', label_key: 'name')).to eq ''
    end
  end
end
