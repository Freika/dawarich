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

    context 'when min_minutes_spent_in_city is 5 (regression for issue #2207)' do
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

      context 'when points have a gap larger than threshold (passing through)' do
        let(:kwargs) { { min_minutes_spent_in_city: 60, max_gap_minutes: 120 } }

        let(:points) do
          [
            # User in Berlin at 9:00, leaves, returns at 11:30
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 15.minutes),
            # 135-minute gap here (user left the city, exceeds 120-min default)
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 150.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 160.minutes)
          ]
        end

        it 'only counts time between consecutive points within threshold' do
          # 15 min (0->15) + 10 min (150->160) = 25 minutes
          # Since 25 < 60, Berlin should be filtered out
          expect(countries_and_cities).to eq(
            [
              CountriesAndCities::CountryData.new(
                country: 'Germany',
                cities: []
              )
            ]
          )
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
