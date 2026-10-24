# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Date and time preferences in I18n.l' do
  let(:zone) { ActiveSupport::TimeZone['UTC'] }
  let(:objects) do
    {
      'date' => { 'single_digit_day' => Date.new(2026, 3, 5), 'two_digit_day' => Date.new(2026, 10, 24) },
      'time' => { 'morning' => zone.local(2026, 3, 5, 9, 7, 4), 'afternoon' => zone.local(2026, 10, 24, 14, 5, 30) }
    }
  end
  let(:date) { Date.new(2026, 10, 24) }
  let(:afternoon) { zone.local(2026, 10, 24, 14, 5, 30) }
  let(:morning) { zone.local(2026, 3, 5, 9, 7, 4) }

  def with_preferences(**preferences, &)
    Users::DateTimePreferences.with(Users::DateTimePreferences.new(**preferences), &)
  end

  def localize(object, format, locale: :en, **preferences)
    with_preferences(**preferences) { I18n.l(object, format:, locale:) }
  end

  describe 'default preferences' do
    let(:baseline) { YAML.load_file(Rails.root.join('spec/fixtures/i18n_localize_baseline.yml')) }
    let(:changed_on_purpose) do
      {
        %w[en time.long_with_time] => {
          'morning' => 'March 05, 2026 at 09:07', 'afternoon' => 'October 24, 2026 at 14:05'
        },
        %w[en time.short_with_time] => { 'morning' => 'Mar 05 at 09:07', 'afternoon' => 'Oct 24 at 14:05' }
      }
    end

    it 'renders every format in every locale exactly as before, except the two English 12h formats' do
      baseline.each do |locale, formats|
        formats.each do |type_and_key, expected_by_object|
          type, key = type_and_key.split('.', 2)
          expected = changed_on_purpose.fetch([locale, type_and_key], expected_by_object)

          actual = expected_by_object.keys.index_with do |label|
            I18n.l(objects.fetch(type).fetch(label), format: key.to_sym, locale: locale.to_sym)
          end

          expect(actual).to eq(expected), "#{locale} #{type_and_key}"
        end
      end
    end
  end

  describe 'date presets' do
    it 'renders full dates with the preset in every locale' do
      %i[en de zh].each do |locale|
        expect(localize(date, :medium, locale:, date_format: 'dd.mm.yyyy')).to eq('24.10.2026')
      end
    end

    it 'renders each preset' do
      expect(localize(date, :long, date_format: 'dd/mm/yyyy')).to eq('24/10/2026')
      expect(localize(date, :day_month_year, date_format: 'mm/dd/yyyy')).to eq('10/24/2026')
      expect(localize(date, :month_day_year, date_format: 'yyyy-mm-dd')).to eq('2026-10-24')
      expect(localize(Date.new(2026, 3, 5), :medium_padded, date_format: 'dd.mm.yyyy')).to eq('05.03.2026')
    end

    it 'renders full datetimes as preset date and time' do
      expect(localize(afternoon, :human, date_format: 'dd.mm.yyyy')).to eq('24.10.2026, 14:05')
      expect(localize(afternoon, :human_with_seconds, locale: :de, date_format: 'yyyy-mm-dd'))
        .to eq('2026-10-24, 14:05:30')
      expect(localize(afternoon, :long_with_time, date_format: 'mm/dd/yyyy')).to eq('10/24/2026, 14:05')
    end

    it 'leaves short labels localized' do
      %i[short_month_day month_year month_name weekday_month_day short].each do |key|
        expect(localize(date, key, locale: :de, date_format: 'mm/dd/yyyy'))
          .to eq(I18n.l(date, format: key, locale: :de))
      end
    end
  end

  describe 'time formats' do
    it 'renders 12h times with the English meridiem' do
      expect(localize(afternoon, :hour_minute, time_format: '12h')).to eq('2:05 PM')
      expect(localize(morning, :hour_minute, time_format: '12h')).to eq('9:07 AM')
      expect(localize(afternoon, :human, date_format: 'mm/dd/yyyy', time_format: '12h')).to eq('10/24/2026, 2:05 PM')
      expect(localize(afternoon, :human_with_seconds, date_format: 'mm/dd/yyyy', time_format: '12h'))
        .to eq('10/24/2026, 2:05:30 PM')
    end

    it 'renders 12h times with the locale-owned clock in auto date mode' do
      expect(localize(afternoon, :long_with_time, locale: :de, time_format: '12h')).to eq('24. Oktober 2026 um 2:05 PM')
      expect(localize(afternoon, :hour_minute, locale: :zh, time_format: '12h')).to eq('下午2:05')
      expect(localize(afternoon, :hour_minute, locale: :es, time_format: '12h')).to eq('2:05 p. m.')
      expect(localize(afternoon, :short, locale: :fr, time_format: '12h')).to eq('24 oct. 2:05 PM')
      expect(localize(afternoon, :short_with_time, time_format: '12h')).to eq('Oct 24 at 2:05 PM')
      expect(localize(afternoon, :human_with_seconds, time_format: '12h')).to eq('24 Oct 2026, 2:05:30 PM')
    end

    it 'keeps the locale wording for 24h' do
      expect(localize(afternoon, :long_with_time, locale: :de, time_format: '24h'))
        .to eq('24. Oktober 2026 um 14:05 Uhr')
      expect(localize(afternoon, :short, locale: :fr, time_format: '24h')).to eq('24 oct. 14h05')
    end

    it 'leaves unclassified time formats alone' do
      expect(localize(afternoon, :default, locale: :fr, time_format: '12h'))
        .to eq(I18n.l(afternoon, format: :default, locale: :fr))
    end
  end

  it 'passes string formats through untouched' do
    expect(localize(date, '%A %d.%m', date_format: 'yyyy-mm-dd', time_format: '12h')).to eq('Saturday 24.10')
  end

  it 'does not change the stored locale formats' do
    localize(afternoon, :human, date_format: 'dd.mm.yyyy', time_format: '12h')
    localize(afternoon, :long_with_time, locale: :de, time_format: '12h')

    expect(I18n.t('time.formats.human', locale: :en)).to eq('%e %b %Y, %H:%M')
    expect(I18n.t('time.formats.long_with_time', locale: :de)).to eq('%-d. %B %Y um %H:%M Uhr')
  end
end
