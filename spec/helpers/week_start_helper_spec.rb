# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeekStartHelper, type: :helper do
  def as_sunday_user(&)
    Users::DateTimePreferences.with(Users::DateTimePreferences.new(first_day_of_week: 'sunday'), &)
  end

  describe '#week_start' do
    it 'follows the active preferences' do
      expect(helper.week_start).to eq(:monday)
      expect(as_sunday_user { helper.week_start }).to eq(:sunday)
    end
  end

  describe '#week_ordered' do
    let(:monday_first) { %w[Mon Tue Wed Thu Fri Sat Sun] }

    it 'keeps Monday-first arrays for a Monday week start' do
      expect(helper.week_ordered(monday_first)).to eq(monday_first)
    end

    it 'moves Sunday to the front for a Sunday week start' do
      expect(as_sunday_user { helper.week_ordered(monday_first) }).to eq(%w[Sun Mon Tue Wed Thu Fri Sat])
    end
  end
end
