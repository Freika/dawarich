# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A country stored under two spellings counts as one country' do
  let(:user) { create(:user, settings: { 'min_minutes_spent_in_city' => 60 }) }
  let(:started_at) { Time.utc(2025, 4, 15, 8) }
  let(:canonical) { 'United States of America' }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  def track(country, city, minutes, velocity: 0)
    minutes.map do |minute|
      # Made-up ocean coordinates with synthetic, pre-geocoded country labels.
      create(:point, user:, country_name: country, city:, velocity:,
                     timestamp: (started_at + minute.minutes).to_i,
                     lonlat: "POINT(#{-140 + minute * 0.00001} -50)",
                     reverse_geocoded_at: Time.current)
    end
  end

  describe 'freshly calculated summaries' do
    before do
      track('United States', 'Boston', [0, 15, 30, 45, 60, 75])
      track(canonical, 'Austin', [120, 135, 150, 165, 180, 195])
      track('The Gambia', 'Synthetic Flyover', [90, 100], velocity: 250)

      Stats::CalculateMonth.new(user.id, 2025, 4).call
    end

    it 'writes a single country with the cities of both spellings into the month stat' do
      toponyms = user.stats.find_by!(year: 2025, month: 4)[:toponyms]

      expect(toponyms.map { |entry| entry['country'] }).to eq([canonical])
      expect(toponyms.first['cities'].map { |city| city['city'] }).to contain_exactly('Boston', 'Austin')
    end

    it 'reports one country in the yearly digest and keeps the flyover out' do
      digest = Users::Digests::CalculateYear.new(user.id, 2025).call

      aggregate_failures do
        expect(digest.countries_count).to eq(1)
        expect(digest.first_time_countries).to eq([canonical])
        expect(digest.top_countries_by_time)
          .to eq([{ 'name' => canonical, 'minutes' => Users::Digests::CalculateYear::MINUTES_PER_DAY }])
      end
    end

    it 'reports one country in the monthly digest and keeps the flyover out' do
      digest = Users::Digests::CalculateMonth.new(user.id, 2025, 4).call

      expect(digest.top_countries_by_time)
        .to eq([{ 'name' => canonical, 'minutes' => Users::Digests::CalculateMonth::MINUTES_PER_DAY }])
    end
  end

  describe 'a stat stored before the spellings were unified' do
    let(:stat) do
      create(:stat, user:, year: 2025, month: 4, toponyms: [
               { 'country' => 'United States', 'cities' => [
                 { 'city' => 'Boston', 'points' => 2, 'timestamp' => 100, 'stayed_for' => 30 }
               ] },
               { 'country' => canonical, 'cities' => [
                 { 'city' => 'Boston', 'points' => 3, 'timestamp' => 200, 'stayed_for' => 45 },
                 { 'city' => 'Austin', 'points' => 1, 'timestamp' => 150, 'stayed_for' => 60 }
               ] },
               { 'country' => 'Atlantis', 'cities' => [] },
               { 'country' => nil, 'cities' => [] }
             ])
    end

    it 'reads as one entry per country' do
      expect(stat.toponyms.map { |entry| entry['country'] }).to eq([canonical, 'Atlantis', nil])
    end

    it 'adds up a city recorded under both spellings' do
      cities = stat.toponyms.first['cities']

      expect(cities).to contain_exactly(
        { 'city' => 'Boston', 'points' => 5, 'timestamp' => 200, 'stayed_for' => 75 },
        { 'city' => 'Austin', 'points' => 1, 'timestamp' => 150, 'stayed_for' => 60 }
      )
    end

    it 'does not report the merge as malformed data' do
      allow(ExceptionReporter).to receive(:call)

      stat.toponyms

      expect(ExceptionReporter).not_to have_received(:call)
    end
  end

  describe 'a digest stored before the spellings were unified' do
    let(:digest) do
      create(:users_digest, user:, year: 2025, sharing_settings: { 'enabled' => true },
             toponyms: [
               { 'country' => 'United States', 'cities' => [{ 'city' => 'Boston' }] },
               { 'country' => canonical, 'cities' => [{ 'city' => 'Boston' }, { 'city' => 'Austin' }] },
               { 'country' => 'Atlantis' }
             ],
             first_time_visits: { 'countries' => ['United States', canonical, 'Atlantis'], 'cities' => ['Boston'] },
             time_spent_by_location: {
               'countries' => [
                 { 'name' => 'Atlantis', 'minutes' => 100 },
                 { 'name' => 'United States', 'minutes' => 60 },
                 { 'name' => canonical, 'minutes' => 90 }
               ],
               'cities' => [{ 'name' => 'Boston', 'minutes' => 60 }]
             })
    end

    it 'reads as one entry per country' do
      aggregate_failures do
        expect(digest.toponyms.map { |entry| entry['country'] }).to eq([canonical, 'Atlantis'])
        expect(digest.toponyms.first['cities'].map { |city| city['city'] }).to contain_exactly('Boston', 'Austin')
        expect(digest.countries_count).to eq(2)
        expect(digest.cities_count).to eq(2)
        expect(digest.first_time_countries).to eq([canonical, 'Atlantis'])
      end
    end

    it 'adds up the time spent under both spellings and keeps the longest stay first' do
      expect(digest.top_countries_by_time).to eq([{ 'name' => canonical, 'minutes' => 150 },
                                                  { 'name' => 'Atlantis', 'minutes' => 100 }])
    end

    it 'serves merged countries from the API serializer' do
      json = Api::DigestDetailSerializer.new(digest, distance_unit: 'km').call

      aggregate_failures do
        expect(json[:toponyms][:countriesCount]).to eq(2)
        expect(json[:toponyms][:countries].map { |entry| entry[:country] }).to eq([canonical, 'Atlantis'])
        expect(json[:firstTimeVisits]['countries']).to eq([canonical, 'Atlantis'])
        expect(json[:timeSpentByLocation]['countries'].first).to eq({ 'name' => canonical, 'minutes' => 150 })
      end
    end

    it 'shows each country once on the public page', type: :request do
      get shared_users_digest_url(digest.sharing_uuid)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(canonical)
        expect(response.body).not_to match(/United States(?! of America)/)
      end
    end

    it 'leaves the stored digest as it was' do
      digest.toponyms
      digest.save!

      stored = digest.reload

      aggregate_failures do
        expect(stored[:toponyms].map { |entry| entry['country'] }).to eq(['United States', canonical, 'Atlantis'])
        expect(stored[:first_time_visits]['countries']).to eq(['United States', canonical, 'Atlantis'])
        expect(stored[:time_spent_by_location]['countries'].size).to eq(3)
      end
    end

    it 'keeps the stored order of a digest with no aliased country' do
      plain = create(:users_digest, user:, year: 2024,
                     time_spent_by_location: { 'countries' => [{ 'name' => 'Spain', 'minutes' => 1 },
                                                               { 'name' => 'France', 'minutes' => 9 }] })

      expect(plain.top_countries_by_time.map { |entry| entry['name'] }).to eq(%w[Spain France])
    end
  end

  describe 'trips' do
    let(:trip) do
      create(:trip, user:, started_at:, ended_at: started_at + 4.hours, skip_calculation_enqueue: true)
    end

    it 'calculates one country from both spellings' do
      track('United States', 'Boston', [0, 15])
      track(canonical, 'Austin', [30, 45])
      track(nil, nil, [60])

      trip.calculate_countries

      expect(trip.visited_countries).to eq([canonical])
    end

    it 'lists countries in the order they were first visited' do
      track('Zambia', 'Lusaka', [0])
      track('United States', 'Boston', [15])
      track('Albania', 'Tirana', [30])

      trip.calculate_countries

      expect(trip.visited_countries).to eq(['Zambia', canonical, 'Albania'])
    end

    it 'resolves a point by its linked country first' do
      germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
      track('Deutschland', 'Berlin', [0]).each { |point| point.update_columns(country_id: germany.id) }
      track('Germany', 'Berlin', [15])

      trip.calculate_countries

      expect(trip.visited_countries).to eq(['Germany'])
    end

    context 'when stored before the spellings were unified' do
      before { trip.update_column(:visited_countries, ['Cape Verde', 'Cabo Verde', 'United States']) }

      let(:index) { ->(params) { Trips::IndexQuery.new(user, params) } }

      it 'shows each country once' do
        html = ApplicationController.render(partial: 'trips/countries',
                                            locals: { trip: trip.reload, distance_unit: 'km' })

        expect(trip.canonical_visited_countries).to contain_exactly('Cabo Verde', canonical)
        expect(html).to include(I18n.t('trips.countries.country_count', count: 2))
      end

      it 'leaves the stored list as it was' do
        expect(trip.reload.visited_countries).to eq(['Cape Verde', 'Cabo Verde', 'United States'])
      end

      it 'offers each country once as a filter' do
        expect(index.call({}).countries).to eq(['Cabo Verde', canonical])
      end

      it 'filters by either spelling' do
        expect(index.call({ country: canonical }).call).to contain_exactly(trip)
        expect(index.call({ country: 'Cabo Verde' }).call).to contain_exactly(trip)
      end

      it 'finds the trip by the name the country no longer goes by' do
        trip.update_column(:visited_countries, ['Cabo Verde'])

        expect(index.call({ q: 'Cape Verde' }).call).to contain_exactly(trip)
      end

      context 'when the search term matches no alias' do
        before { trip.update_column(:visited_countries, ['Germany']) }

        it 'still finds the trip by its visited country' do
          expect(Countries::NameAliases.spellings_containing('Germ')).to be_empty
          expect(index.call({ q: 'Germ' }).call).to contain_exactly(trip)
        end

        it 'still finds the trip by its name' do
          trip.update_column(:name, 'Zanzibar weekend')

          expect(index.call({ q: 'Zanzibar' }).call).to contain_exactly(trip)
        end

        it 'finds nothing when no trip matches the term' do
          expect(index.call({ q: 'Atlantis' }).call).to be_empty
        end
      end

      it 'does not match a country the trip never visited' do
        expect(index.call({ country: 'France' }).call).to be_empty
      end
    end
  end
end
