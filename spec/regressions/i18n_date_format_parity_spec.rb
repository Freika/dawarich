# frozen_string_literal: true

require 'rails_helper'

# Locks the rendered output of every named date/time format against the literal
# strftime patterns the application used before the copy was centralised in
# config/locales/en.yml. Single-digit days are the only case where zero- and
# space-padding differ, so every example uses one.
RSpec.describe 'I18n date and time format parity' do
  let(:date) { Date.new(2026, 8, 5) }
  let(:time) { Time.zone.local(2026, 8, 5, 9, 7, 3) }

  describe 'date formats' do
    {
      long: '%B %d, %Y',
      medium: '%b %-d, %Y',
      medium_padded: '%b %d, %Y',
      month_day: '%B %-d',
      month_day_padded: '%B %d',
      month_day_year: '%B %-d, %Y',
      short_month_day: '%b %-d',
      short_month_day_padded: '%b %d',
      day_month_year: '%e %B %Y',
      day_month_year_abbreviated: '%-d %b %Y',
      day_year: '%-d, %Y',
      iso: '%Y-%m-%d',
      month_name: '%B',
      abbreviated_month_name: '%b',
      month_year: '%B %Y',
      weekday_month_day: '%A, %B %-d',
      short_month_day_weekday: '%b %-d, %A',
      short_weekday_month_day: '%a, %b %-d'
    }.each do |format, pattern|
      it "renders :#{format} as #{pattern}" do
        expect(I18n.l(date, format:)).to eq(date.strftime(pattern))
      end
    end
  end

  describe 'time formats' do
    {
      hour_minute: '%H:%M',
      human: '%e %b %Y, %H:%M',
      human_with_seconds: '%e %b %Y, %H:%M:%S',
      long_with_time: '%B %d, %Y at %I:%M %p',
      short_with_time: '%b %d at %I:%M %p'
    }.each do |format, pattern|
      it "renders :#{format} as #{pattern}" do
        expect(I18n.l(time, format:)).to eq(time.strftime(pattern))
      end
    end
  end
end
