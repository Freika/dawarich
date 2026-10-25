# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TripsHelper, type: :helper do
  describe '#planned_note_time' do
    def note_time(value, time_format)
      Users::DateTimePreferences.with(Users::DateTimePreferences.new(time_format:)) do
        helper.planned_note_time(value)
      end
    end

    it 'renders the stored clock time with the time format' do
      expect(note_time('14:05:00', 'auto')).to eq('14:05')
      expect(note_time('14:05:00', '12h')).to eq('2:05 PM')
      expect(note_time('9:30', '12h')).to eq('9:30 AM')
    end

    it 'keeps values that are not a clock time' do
      expect(note_time('morning', '12h')).to eq('morning')
    end
  end
end
