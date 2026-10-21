# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trips index search, filters and sorting', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

  def trip(name, **attrs)
    create(:trip, { user:, name:, description: 'Plain words',
                    started_at: Time.utc(2024, 6, 10), ended_at: Time.utc(2024, 6, 12) }.merge(attrs))
  end

  def listed_names
    Nokogiri::HTML(response.body).css('[data-testid="trip-card-name"]').map { _1.text.strip }
  end

  before { sign_in user }

  describe 'malformed input' do
    it 'ignores NUL bytes in the search and country filters' do
      trip('Lisbon weekend', visited_countries: ['Portugal'])

      get trips_path(q: "lis\u0000bon", country: "Portu\u0000gal")

      expect(response).to have_http_status(:ok)
      expect(listed_names).to eq(['Lisbon weekend'])
    end
  end

  describe 'search' do
    it 'matches the trip name, case-insensitively' do
      trip('Lisbon weekend')
      trip('Alps hike')

      get trips_path(q: 'lisbon')

      expect(listed_names).to eq(['Lisbon weekend'])
    end

    it 'matches the description text but not its markup' do
      trip('Coast', description: '<div>Seafood and surfing</div>')
      trip('Mountains', description: 'Snow')

      get trips_path(q: 'surfing')
      expect(listed_names).to eq(['Coast'])

      get trips_path(q: 'div')
      expect(listed_names).to be_empty
    end

    it 'matches trip notes' do
      noted = trip('Noted')
      trip('Silent')
      create(:note, user:, attachable: noted, noted_at: noted.started_at + 2.hours, title: 'Day one',
                   body: 'Found a hidden bakery')

      get trips_path(q: 'bakery')

      expect(listed_names).to eq(['Noted'])
    end

    it 'matches planned places, stops, accommodations, reservations and days' do
      stops = trip('Stops')
      day = stops.planned_days.create!(date: Date.new(2024, 6, 10), position: 0, title: 'Arrival')
      day.planned_stops.create!(name: 'Belem Tower', position: 0)
      trip('Unplanned').planned_unplanned_places.create!(name: 'Sintra Palace', position: 0)
      trip('Hotel').planned_accommodations.create!(name: 'Casa Azul', address: 'Rua Augusta 1')
      trip('Train').planned_reservations.create!(title: 'Night train', location: 'Porto Campanha')
      trip('Unrelated')

      expect_search = lambda do |query, names|
        get trips_path(q: query)
        expect(listed_names).to match_array(names)
      end

      expect_search.call('belem', ['Stops'])
      expect_search.call('arrival', ['Stops'])
      expect_search.call('sintra', ['Unplanned'])
      expect_search.call('augusta', ['Hotel'])
      expect_search.call('campanha', ['Train'])
    end

    it 'matches visited countries' do
      trip('Iberia', visited_countries: %w[Portugal Spain])
      trip('Home')

      get trips_path(q: 'spain')

      expect(listed_names).to eq(['Iberia'])
    end

    it 'matches description text with escaped characters' do
      trip('Pub', description: 'Fish & chips by the sea')
      trip('Cafe', description: 'Tea and cake')

      get trips_path(q: 'fish & chips')
      expect(listed_names).to eq(['Pub'])

      get trips_path(q: 'amp')
      expect(listed_names).to be_empty
    end

    it 'matches countries by name only, not by their stored punctuation' do
      trip('Iberia', visited_countries: %w[Portugal Spain])
      trip('Not calculated', visited_countries: {})

      get trips_path(q: '"')
      expect(listed_names).to be_empty

      get trips_path(q: '{')
      expect(listed_names).to be_empty
    end

    it 'never lists trips of other users' do
      trip('Mine in Lisbon')
      create(:trip, name: 'Theirs in Lisbon', started_at: Time.utc(2024, 6, 10), ended_at: Time.utc(2024, 6, 12))

      get trips_path(q: 'lisbon')

      expect(listed_names).to eq(['Mine in Lisbon'])
    end

    it 'treats LIKE wildcards literally' do
      trip('100% fun')
      trip('Boring')

      get trips_path(q: '%')

      expect(listed_names).to eq(['100% fun'])
    end

    it 'lists a trip once even when several of its parts match' do
      both = trip('Porto', description: 'Porto port wine')
      both.planned_unplanned_places.create!(name: 'Porto Cathedral', position: 0)

      get trips_path(q: 'porto')

      expect(listed_names).to eq(['Porto'])
    end
  end

  describe 'year and month filters' do
    it 'keeps trips that overlap the chosen year, in the user time zone' do
      trip('Last year', started_at: Time.utc(2023, 3, 1), ended_at: Time.utc(2023, 3, 5))
      trip('Across new year', started_at: Time.utc(2023, 12, 30), ended_at: Time.utc(2024, 1, 2))
      trip('Berlin new year', started_at: Time.utc(2023, 12, 31, 23, 30), ended_at: Time.utc(2023, 12, 31, 23, 45))

      get trips_path(year: 2024)

      expect(listed_names).to match_array(['Across new year', 'Berlin new year'])
    end

    it 'narrows a year to a month' do
      trip('June', started_at: Time.utc(2024, 6, 1), ended_at: Time.utc(2024, 6, 3))
      trip('July', started_at: Time.utc(2024, 7, 10), ended_at: Time.utc(2024, 7, 12))
      trip('June to July', started_at: Time.utc(2024, 6, 28), ended_at: Time.utc(2024, 7, 2))

      get trips_path(year: 2024, month: 7)

      expect(listed_names).to match_array(['July', 'June to July'])
    end

    it 'ignores a month given without a year' do
      trip('June', started_at: Time.utc(2024, 6, 1), ended_at: Time.utc(2024, 6, 3))
      trip('July', started_at: Time.utc(2024, 7, 10), ended_at: Time.utc(2024, 7, 12))

      get trips_path(month: 7)

      expect(listed_names).to match_array(%w[June July])
    end

    it 'keeps an active year selected even when no trip touches it' do
      trip('June', started_at: Time.utc(2024, 6, 1), ended_at: Time.utc(2024, 6, 3))

      get trips_path(year: 2030)

      selected = Nokogiri::HTML(response.body).at_css('select[name="year"] option[selected]')
      expect(selected['value']).to eq('2030')
    end

    it 'explains why the month is unavailable without a year' do
      trip('June')

      get trips_path

      month = Nokogiri::HTML(response.body).at_css('select[name="month"]')
      hint = Nokogiri::HTML(response.body).at_css("##{month['aria-describedby']}")
      expect(hint.text).to eq(I18n.t('trips.filters.choose_year_first'))
    end

    it 'offers every year a trip touches' do
      trip('Across new year', started_at: Time.utc(2022, 12, 30), ended_at: Time.utc(2024, 1, 2))

      get trips_path

      years = Nokogiri::HTML(response.body).css('select[name="year"] option').map { _1['value'] }.compact_blank
      expect(years).to eq(%w[2024 2023 2022])
    end
  end

  describe 'country filter' do
    it 'keeps trips that visited the country and skips trips without countries yet' do
      trip('Iberia', visited_countries: %w[Portugal Spain])
      trip('France', visited_countries: %w[France])
      trip('Not calculated', visited_countries: {})

      get trips_path(country: 'Spain')

      expect(listed_names).to eq(['Iberia'])
    end

    it 'offers the countries of all trips, sorted' do
      trip('Iberia', visited_countries: %w[Spain Portugal])
      trip('France', visited_countries: %w[France Spain])
      trip('Not calculated', visited_countries: {})

      get trips_path

      options = Nokogiri::HTML(response.body).css('select[name="country"] option').map { _1['value'] }.compact_blank
      expect(options).to eq(%w[France Portugal Spain])
    end
  end

  describe 'sorting' do
    before do
      trip('Bravo', started_at: Time.utc(2024, 1, 1), ended_at: Time.utc(2024, 1, 2), distance: 50)
      trip('alpha', started_at: Time.utc(2024, 3, 1), ended_at: Time.utc(2024, 3, 2), distance: nil)
      trip('Charlie', started_at: Time.utc(2024, 2, 1), ended_at: Time.utc(2024, 2, 2), distance: 900)
    end

    it 'shows the newest trips first by default' do
      get trips_path

      expect(listed_names).to eq(%w[alpha Charlie Bravo])
    end

    it 'sorts by oldest first' do
      get trips_path(sort: 'oldest')

      expect(listed_names).to eq(%w[Bravo Charlie alpha])
    end

    it 'sorts by name, ignoring case' do
      get trips_path(sort: 'name')

      expect(listed_names).to eq(%w[alpha Bravo Charlie])
    end

    it 'sorts by distance, longest first, with uncalculated trips last' do
      get trips_path(sort: 'distance')

      expect(listed_names).to eq(%w[Charlie Bravo alpha])
    end

    it 'falls back to newest first for an unknown sort' do
      get trips_path(sort: 'name; DROP TABLE trips')

      expect(listed_names).to eq(%w[alpha Charlie Bravo])
    end
  end

  describe 'pagination' do
    it 'keeps the search and filters on page links' do
      7.times { |i| trip("Lisbon #{i}", started_at: Time.utc(2024, 6, 1 + i), ended_at: Time.utc(2024, 6, 2 + i)) }

      get trips_path(q: 'lisbon', year: 2024, sort: 'oldest')

      page_two = Nokogiri::HTML(response.body).css('a[href*="page=2"]').first
      expect(page_two).to be_present
      query = Rack::Utils.parse_query(URI(page_two['href']).query)
      expect(query).to include('q' => 'lisbon', 'year' => '2024', 'sort' => 'oldest')
    end
  end

  describe 'empty states' do
    it 'shows the first-trip prompt when the user has no trips' do
      get trips_path

      expect(response.body).to include(I18n.t('trips.index.no_trips_yet'))
      expect(response.body).not_to include('name="q"')
    end

    it 'shows a no-match message with a reset link when filters hide every trip' do
      trip('Lisbon')

      get trips_path(q: 'nowhere')

      expect(response.body).not_to include(I18n.t('trips.index.no_trips_yet'))
      expect(response.body).to include(I18n.t('trips.index.no_matching_trips'))
      expect(Nokogiri::HTML(response.body).css("a[href='#{trips_path}']")).to be_present
    end
  end
end
