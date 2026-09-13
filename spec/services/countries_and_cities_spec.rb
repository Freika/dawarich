# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call' do
    subject(:countries_and_cities) { described_class.new(points, **kwargs).call }

    let(:kwargs) { {} }
    let(:timestamp) { DateTime.new(2021, 1, 1, 0, 0, 0) }

    let(:points) do
      [
        create(:point, city: 'Berlin', country: 'Germany', timestamp:),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 10.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 30.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 40.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 50.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 60.minutes),
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 70.minutes),
        create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 80.minutes),
        create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 90.minutes)
      ]
    end

    context 'when min_minutes_spent_in_city is 5' do
      let(:kwargs) { { min_minutes_spent_in_city: 5 } }

      let(:points) do
        # Points 15 minutes apart, total duration 75 minutes
        (0..5).map do |i|
          create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 15).minutes)
        end
      end

      it 'counts the city even with a low min_minutes_spent_in_city' do
        expect(countries_and_cities).to eq(
          [
            CountriesAndCities::CountryData.new(
              country: 'Germany',
              cities: [
                CountriesAndCities::CityData.new(
                  city: 'Berlin', points: 6, timestamp: (timestamp + 75.minutes).to_i, stayed_for: 75
                )
              ]
            )
          ]
        )
      end
    end

    context 'when min_minutes_spent_in_city is 60 (default)' do
      let(:kwargs) { { min_minutes_spent_in_city: 60 } }

      context 'when user stayed in the city for more than 1 hour' do
        it 'returns countries and cities' do
          expect(countries_and_cities).to eq(
            [
              CountriesAndCities::CountryData.new(
                country: 'Germany',
                cities: [
                  CountriesAndCities::CityData.new(
                    city: 'Berlin', points: 8, timestamp: 1_609_463_400, stayed_for: 70
                  )
                ]
              ),
              CountriesAndCities::CountryData.new(
                country: 'Belgium',
                cities: []
              )
            ]
          )
        end
      end

      context 'when user stayed in the city for less than 1 hour' do
        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 10.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.minutes),
            create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 80.minutes),
            create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 90.minutes)
          ]
        end

        it 'returns countries and cities' do
          expect(countries_and_cities).to eq(
            [
              CountriesAndCities::CountryData.new(
                country: 'Germany',
                cities: []
              ),
              CountriesAndCities::CountryData.new(
                country: 'Belgium',
                cities: []
              )
            ]
          )
        end
      end

      context 'when tracking falls silent while the user stays in one city' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 15.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 150.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 160.minutes)
          ]
        end

        it 'treats the silence as continued presence' do
          expect(countries_and_cities).to eq(
            [
              CountriesAndCities::CountryData.new(
                country: 'Germany',
                cities: [
                  CountriesAndCities::CityData.new(
                    city: 'Berlin', points: 4, timestamp: (timestamp + 160.minutes).to_i, stayed_for: 160
                  )
                ]
              )
            ]
          )
        end
      end

      context 'when the same city is revisited with another city in between' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Leipzig', country: 'Germany', timestamp:),
            create(:point, city: 'Leipzig', country: 'Germany', timestamp: timestamp + 10.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 3.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 9.hours),
            create(:point, city: 'Leipzig', country: 'Germany', timestamp: timestamp + 20.hours),
            create(:point, city: 'Leipzig', country: 'Germany', timestamp: timestamp + 20.hours + 10.minutes)
          ]
        end

        it 'keeps the short stops apart instead of spanning them' do
          cities = countries_and_cities.first.cities.map(&:city)

          expect(cities).to eq(['Berlin'])
        end
      end

      context 'when a flight separates two stays in the same city' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 30.minutes),
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250',
                           timestamp: timestamp + 3.hours),
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250',
                           timestamp: timestamp + 5.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 21.hours)
          ]
        end

        it 'does not credit the time spent in the air to the city' do
          expect(countries_and_cities.first.cities.first.stayed_for).to eq(90)
        end
      end

      context 'when sparse sampling catches one point over another city mid-flight' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 30.minutes),
            create(:point, city: 'Paris', country: 'France', velocity: '250',
                           timestamp: timestamp + 3.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 21.hours)
          ]
        end

        it 'bridges the trip rather than risk dropping the stay on one sample' do
          cities = countries_and_cities.flat_map(&:cities)

          expect(cities.map(&:city)).to eq(['Berlin'])
          expect(cities.first.stayed_for).to eq(1260)
        end
      end

      context 'when every point is in transit' do
        let(:kwargs) { { min_minutes_spent_in_city: 1 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250',
                           timestamp: timestamp + 1.hour),
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250',
                           timestamp: timestamp + 2.hours)
          ]
        end

        it 'credits no city at all' do
          expect(countries_and_cities).to be_empty
        end
      end

      context 'when a lone velocity spike interrupts a stay' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 30.minutes),
            create(:point, city: 'Berlin', country: 'Germany', velocity: '250',
                           timestamp: timestamp + 3.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 21.hours)
          ]
        end

        it 'does not let one bad reading break the stay apart' do
          expect(countries_and_cities.first.cities.first.stayed_for).to eq(1260)
        end
      end

      context 'when an ungeocoded stretch separates two stays in the same city' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 30.minutes),
            create(:point, city: nil, country: nil, timestamp: timestamp + 3.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.hours),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 21.hours)
          ]
        end

        it 'treats the ungeocoded points as silence rather than as leaving' do
          expect(countries_and_cities.first.cities.first.stayed_for).to eq(1260)
        end
      end

      context 'when a gap sits exactly on the bridge cap' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 7.days)
          ]
        end

        it 'bridges the silence rather than splitting it' do
          cities = countries_and_cities.first.cities

          expect(cities.map(&:city)).to eq(['Berlin'])
          expect(cities.first.stayed_for).to eq(7 * 24 * 60)
        end
      end

      context 'when a gap exceeds the bridge cap' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 10.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 8.days),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 8.days + 10.minutes)
          ]
        end

        it 'splits the runs rather than crediting the whole gap' do
          expect(countries_and_cities.first.cities).to be_empty
        end
      end

      context 'when points share a timestamp at a city boundary' do
        let(:kwargs) { { min_minutes_spent_in_city: 1 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 100.minutes),
            create(:point, city: 'Munich', country: 'Germany', timestamp: timestamp + 100.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 100.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 200.minutes)
          ]
        end

        it 'credits the same duration regardless of input order' do
          durations = Array.new(20) do
            described_class.new(points.shuffle, **kwargs)
                           .call.first.cities.find { |city| city.city == 'Berlin' }&.stayed_for
          end

          expect(durations.uniq).to eq([200])
        end
      end

      context 'when a city holds a single point' do
        let(:kwargs) { { min_minutes_spent_in_city: 1 } }

        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Munich', country: 'Germany', timestamp: timestamp + 3.hours),
            create(:point, city: 'Hamburg', country: 'Germany', timestamp: timestamp + 6.hours),
            create(:point, city: 'Hamburg', country: 'Germany', timestamp: timestamp + 8.hours)
          ]
        end

        it 'credits it no duration' do
          cities = countries_and_cities.first.cities

          expect(cities.map(&:city)).to eq(['Hamburg'])
        end
      end

      context 'when points span a long time but have continuous presence' do
        it 'counts the full duration when all intervals are within threshold' do
          points_data = (0..5).map do |i|
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 30).minutes)
          end

          result = described_class.new(points_data, min_minutes_spent_in_city: 60).call

          # 5 intervals of 30 minutes each = 150 minutes total
          expect(result).to eq(
            [
              CountriesAndCities::CountryData.new(
                country: 'Germany',
                cities: [
                  CountriesAndCities::CityData.new(
                    city: 'Berlin', points: 6, timestamp: (timestamp + 150.minutes).to_i, stayed_for: 150
                  )
                ]
              )
            ]
          )
        end
      end

      context 'when points are high-frequency (sub-minute intervals)' do
        let(:kwargs) { { min_minutes_spent_in_city: 60 } }

        let(:points) do
          # Simulate OwnTracks ~5 second intervals over 3 hours (2160 points)
          # Previously, integer division (5/60==0) would make duration ~0
          (0..359).map do |i|
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 30).seconds)
          end
        end

        it 'correctly accumulates sub-minute intervals into total duration' do
          result = countries_and_cities

          berlin = result.find { |c| c.country == 'Germany' }&.cities&.find { |c| c.city == 'Berlin' }
          expect(berlin).not_to be_nil
          # 359 intervals of 30 seconds = 10770 seconds = 179 minutes
          expect(berlin.stayed_for).to eq(179)
        end
      end

      context 'when points have different country_name spellings but same country_id' do
        let(:kwargs) { { min_minutes_spent_in_city: 5 } }

        let(:country) do
          Country.find_or_create_by!(name: 'Tanzania') do |c|
            c.iso_a2 = 'TZ'
            c.iso_a3 = 'TZA'
            c.geom = 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
          end
        end

        let(:points) do
          [
            create(:point, city: 'Dar es Salaam', country: country, timestamp:),
            create(:point, city: 'Dar es Salaam', country: country, timestamp: timestamp + 10.minutes),
            create(:point, city: 'Dar es Salaam', country: country, timestamp: timestamp + 20.minutes)
          ].tap do |pts|
            # Simulate geocoder returning a different spelling for the same country
            pts.last.update_column(:country_name, 'United Republic of Tanzania')
          end
        end

        it 'groups them under the canonical country name' do
          result = countries_and_cities
          country_names = result.map(&:country)

          expect(country_names).to eq(['Tanzania'])
          expect(result.size).to eq(1)
        end
      end

      context 'when points have no country_id' do
        let(:kwargs) { { min_minutes_spent_in_city: 5 } }

        let(:points) do
          (0..3).map do |i|
            create(:point, city: 'Unknown City', timestamp: timestamp + (i * 10).minutes).tap do |p|
              p.update_columns(country_name: 'Somewhere', country_id: nil)
            end
          end
        end

        it 'falls back to raw country_name' do
          result = countries_and_cities
          expect(result.map(&:country)).to eq(['Somewhere'])
        end
      end
    end
  end
end
