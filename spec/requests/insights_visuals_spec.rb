# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights visuals', type: :request do
  let(:user) { create(:user) }

  def doc = Nokogiri::HTML(response.body)

  before { sign_in user }

  describe 'year calendar and country timeline' do
    def visit_country(name, date)
      create(:point, user:, country_name: name, timestamp: Time.zone.parse("#{date} 12:00").to_i)
    end

    before do
      create(:stat, user:, year: 2025, month: 3, distance: 40_000, daily_distance: { '4' => 25_000, '6' => 15_000 })
      visit_country('Germany', '2025-03-04')
      visit_country('Czechia', '2025-03-06')
    end

    it 'loads the calendar with countries lazily on the year view' do
      get insights_path(year: 2025)

      expect(doc.at_css('turbo-frame#residency-content')['src']).to eq(map_residency_path(year: 2025))
      expect(doc.at_css('[data-testid="year-calendar"]')).to be_nil
    end

    it 'colours each day by its country and keeps the distance' do
      get map_residency_path(year: 2025)

      cell = doc.at_css('.year-calendar__cell[data-date="2025-03-06"]')
      expect(cell['data-country']).to eq('Czechia')
      expect(cell['data-distance']).to be_present
      expect(doc.css('[data-action="year-calendar#setMode"]').map do
        _1['data-mode']
      end).to eq(%w[both distance countries])
    end

    it 'lists the countries and draws a timeline lane for each' do
      get map_residency_path(year: 2025)

      expect(doc.css('[data-testid="year-calendar-countries"] button').map do
        _1['data-country']
      end).to include('Germany', 'Czechia')
      segments = doc.css('[data-testid="country-ribbon"] .country-ribbon__segment').map { _1['aria-label'] }
      expect(segments).to include(a_string_including('Czechia'))
      expect(doc.at_css('.country-ribbon__today')).to be_nil
    end

    it 'explains that countries follow UTC days while distances follow the user time zone' do
      user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin'))

      get map_residency_path(year: 2025)

      note = doc.at_css('[data-testid="year-calendar-timezone-note"]')
      expect(note.text).to include('UTC', 'Europe/Berlin')
    end

    it 'leaves the time zone note out when the user is on UTC' do
      user.update!(settings: user.settings.merge('timezone' => 'Etc/UTC'))

      get map_residency_path(year: 2025)

      expect(doc.at_css('[data-testid="year-calendar-timezone-note"]')).to be_nil
    end

    it 'places the race next to the country timeline' do
      get map_residency_path(year: 2025)

      row = doc.at_css('[data-testid="insights-distance-row"]')
      expect(row.at_css('[data-testid="country-ribbon"]')).to be_present
      expect(row.at_css('[data-testid="distance-race"]')).to be_present
    end

    it 'caps the timeline at eight countries and counts the rest' do
      %w[France Spain Italy Austria Poland Denmark Belgium Portugal].each_with_index do |name, index|
        visit_country(name, "2025-04-#{format('%02d', index + 1)}")
      end

      get map_residency_path(year: 2025)

      expect(doc.css('[data-testid="country-ribbon-lane"]').size).to eq(8)
      more = I18n.t('insights.country_ribbon.more_countries', count: 2)
      expect(doc.at_css('[data-testid="country-ribbon"]').text).to include(more)
    end

    it 'shows an activity-only calendar inline for a Lite user on Cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      create(:stat, user:, year: Time.current.year - 1, month: 1, distance: 1_000)
      create(:stat, user:, year: Time.current.year, month: Time.current.month, distance: 5_000,
                    daily_distance: { '1' => 5_000 })

      get insights_path(year: Time.current.year)

      calendar = doc.at_css('[data-testid="year-calendar"]')
      expect(calendar).to be_present
      expect(calendar.at_css('.year-calendar')['data-mode']).to eq('distance')
      expect(calendar.css('[data-action="year-calendar#setMode"]')).to be_empty
      expect(doc.at_css('turbo-frame#residency-content')).to be_nil
      expect(doc.at_css('[data-testid="distance-race"]')).to be_nil
      expect(doc.at_css('[data-testid="distance-race-locked"]').text)
        .to include("#{Time.current.year} vs #{Time.current.year - 1}")
    end
  end

  describe 'race for a Lite user' do
    it 'leaves the locked race out for a Lite user without a previous year' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      create(:stat, user:, year: Time.current.year, month: Time.current.month, distance: 5_000)

      get insights_path(year: Time.current.year)

      expect(doc.at_css('[data-testid="distance-race-locked"]')).to be_nil
    end
  end

  describe 'year without detected countries' do
    it 'explains that countries need reverse geocoding' do
      create(:stat, user:, year: 2025, month: 3, distance: 40_000, daily_distance: { '4' => 25_000 })

      get map_residency_path(year: 2025)

      expect(doc.at_css('[data-testid="residency-no-countries"]').text)
        .to include('Points need reverse geocoding to detect countries.')
    end
  end

  describe 'year cards' do
    before do
      create(:stat, user:, year: 2025, month: 5, distance: 50_000)
      create(:stat, user:, year: 2024, month: 5, distance: 20_000)
      create(:track, user:, original_path: 'LINESTRING(13.40 52.52, 14.42 50.08)',
                     start_at: Time.utc(2025, 5, 3, 10), end_at: Time.utc(2025, 5, 3, 14))
    end

    it 'loads the routes of a year into its map after the page and shows a strip of its months' do
      get insights_path(year: 'all')

      card = doc.css('[data-testid="insights-year-card"]').find { _1.text.include?('2025') }
      map = card.at_css('[data-testid="insights-year-map"]')
      expect(map['data-trip-maplibre-preview-lines-url-value']).to eq(routes_insights_path(year: 2025))
      expect(card.css('[data-testid="insights-year-strip"] span').size).to eq(12)
    end

    it 'serves the routes of a year as JSON' do
      get routes_insights_path(year: 2025)

      expect(response.parsed_body['lines']).to eq([[[13.4, 52.52], [14.42, 50.08]]])
    end

    it 'keeps serving the built routes until a track of the year changes' do
      get routes_insights_path(year: 2025)
      Track.update_all(original_path: 'LINESTRING(2.35 48.86, 4.84 45.76)')

      get routes_insights_path(year: 2025)
      expect(response.parsed_body['lines']).to eq([[[13.4, 52.52], [14.42, 50.08]]])

      Track.first.touch
      get routes_insights_path(year: 2025)
      expect(response.parsed_body['lines']).to eq([[[2.35, 48.86], [4.84, 45.76]]])
    end

    it 'does not rerun a failed route query on every view' do
      allow(ExceptionReporter).to receive(:call)
      allow_any_instance_of(Stats::YearRoutesQuery).to receive(:call)
        .and_raise(ActiveRecord::QueryCanceled, 'statement timeout')

      2.times { get routes_insights_path(year: 2025) }

      expect(response.parsed_body['lines']).to eq([])
      expect(ExceptionReporter).to have_received(:call).once
    end

    it 'serves no routes from outside a Lite data window' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      old = 3.years.ago.year
      create(:track, user:, original_path: 'LINESTRING(2.35 48.86, 4.84 45.76)',
                     start_at: Time.utc(old, 5, 3, 10), end_at: Time.utc(old, 5, 3, 14))

      get routes_insights_path(year: old)

      expect(response.parsed_body['lines']).to eq([])
    end

    it 'answers with no routes instead of failing when the geometry query breaks' do
      allow_any_instance_of(Stats::YearRoutesQuery).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'boom')

      get routes_insights_path(year: 2025)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['lines']).to eq([])
    end

    it 'leaves the map out for a year without tracks' do
      get insights_path(year: 'all')

      card = doc.css('[data-testid="insights-year-card"]').find { _1.text.include?('2024') }
      expect(card.at_css('[data-testid="insights-year-map"]')).to be_nil
      expect(card.at_css('[data-testid="insights-year-strip"]')).to be_present
    end
  end

  describe 'race against the previous year' do
    it 'draws both years and how far ahead this year is' do
      create(:stat, user:, year: 2025, month: 3, distance: 30_000, daily_distance: { '1' => 30_000 })
      create(:stat, user:, year: 2024, month: 3, distance: 10_000, daily_distance: { '1' => 10_000 })

      get map_residency_path(year: 2025)

      race = doc.at_css('[data-testid="distance-race"]')
      expect(race).to be_present
      expect(race.css('[data-race-line]').map { _1['data-race-line'] }).to contain_exactly('current', 'previous')
      expect(race.at_css('[data-testid="distance-race-lead"]').text).to include('20')
    end

    it 'draws only this year when the previous one has no data' do
      create(:stat, user:, year: 2025, month: 3, distance: 30_000, daily_distance: { '1' => 30_000 })

      get map_residency_path(year: 2025)

      race = doc.at_css('[data-testid="distance-race"]')
      expect(race.css('[data-race-line]').map { _1['data-race-line'] }).to eq(['current'])
      expect(race.at_css('[data-testid="distance-race-lead"]')).to be_nil
    end

    it 'is not part of the all-time view' do
      create(:stat, user:, year: 2025, month: 3, distance: 30_000, daily_distance: { '1' => 30_000 })

      get insights_path(year: 'all')

      expect(doc.at_css('[data-testid="distance-race"]')).to be_nil
    end
  end
end
