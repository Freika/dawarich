# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Activity heatmap mobile default scroll target', type: :helper do
  describe '#most_recent_active_date' do
    it 'returns nil when daily_data is empty' do
      expect(helper.most_recent_active_date({})).to be_nil
    end

    it 'returns nil when no day has positive distance' do
      data = { '2026-01-01' => 0, '2026-02-10' => nil }
      expect(helper.most_recent_active_date(data)).to be_nil
    end

    it 'returns the latest date string with a positive distance' do
      data = {
        '2026-01-05' => 1200,
        '2026-02-10' => 800,
        '2026-02-15' => 0,
        '2026-01-20' => 500
      }
      expect(helper.most_recent_active_date(data)).to eq('2026-02-10')
    end

    it 'ignores zero-distance entries dated after the most recent active day' do
      data = { '2026-03-01' => 1500, '2026-04-01' => 0, '2026-05-01' => 0 }
      expect(helper.most_recent_active_date(data)).to eq('2026-03-01')
    end
  end
end
