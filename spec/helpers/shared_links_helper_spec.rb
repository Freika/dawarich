# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinksHelper, type: :helper do
  describe '#formatted_date_range' do
    def range_with(date_format, start_date, end_date)
      Users::DateTimePreferences.with(Users::DateTimePreferences.new(date_format:)) do
        helper.formatted_date_range(start_date, end_date)
      end
    end

    it 'collapses ranges in the same month with the locale format' do
      expect(range_with('auto', Date.new(2026, 10, 3), Date.new(2026, 10, 5))).to eq('October 3–5, 2026')
    end

    it 'renders both ends with the date preset' do
      expect(range_with('dd.mm.yyyy', Date.new(2026, 10, 3), Date.new(2026, 10, 5))).to eq('03.10.2026 – 05.10.2026')
      expect(range_with('mm/dd/yyyy', Date.new(2026, 1, 3), Date.new(2026, 10, 5))).to eq('01/03/2026 – 10/05/2026')
    end

    it 'renders a single day with the date preset' do
      expect(range_with('yyyy-mm-dd', Date.new(2026, 10, 3), Date.new(2026, 10, 3))).to eq('2026-10-03')
    end
  end
end
