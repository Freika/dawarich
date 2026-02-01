# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call' do
    subject(:countries_and_cities) { described_class.new(points).call }

    # we have 5 points in the same city and country within 1 hour,
    # 5 points in the differnt city within 10 minutes
    # and we expect to get one country with one city which has 5 points

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

    context 'when MIN_MINUTES_SPENT_IN_CITY is 5 (regression for issue #2207)' do
      before do
        stub_const('MIN_MINUTES_SPENT_IN_CITY', 5)
      end

      let(:points) do
        # Points 15 minutes apart, total duration 75 minutes
        (0..5).map do |i|
          create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 15).minutes)
        end
      end

      it 'counts the city even with a low MIN_MINUTES_SPENT_IN_CITY' do
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

    context 'when MIN_MINUTES_SPENT_IN_CITY is 60 (in minutes)' do
      before do
        stub_const('MIN_MINUTES_SPENT_IN_CITY', 60)
      end

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
        let(:points) do
          [
            # User in Berlin at 9:00, leaves, returns at 11:00
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 15.minutes),
            # 105-minute gap here (user left the city)
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 120.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 130.minutes)
          ]
        end

        it 'only counts time between consecutive points within threshold' do
          # Old logic would count 130 minutes (span from first to last)
          # New logic counts: 15 min (0->15) + 10 min (120->130) = 25 minutes
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
        let(:points) do
          # Points every 30 minutes for 2.5 hours = continuous presence
          (0..5).map do |i|
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 30).minutes)
          end
        end

        it 'counts the full duration when all intervals are within threshold' do
          # 5 intervals of 30 minutes each = 150 minutes total
          expect(countries_and_cities).to eq(
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
    end
  end
end
