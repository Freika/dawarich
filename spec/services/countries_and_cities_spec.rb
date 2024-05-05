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

    context 'when MIN_MINUTES_SPENT_IN_CITY is 60 (in minutes)' do
      before do
        stub_const('MIN_MINUTES_SPENT_IN_CITY', 60)
      end

      context 'when user stayed in the city for more than 1 hour' do
        it 'returns countries and cities' do
          expect(countries_and_cities).to eq(
            [
              {
                cities: [{ city: 'Berlin', points: 8, timestamp: 1609463400, stayed_for: 70 }],
                country: 'Germany'
              },
              {
                cities: [], country: 'Belgium'
              }
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
              {
                cities: [], country: 'Germany'
              },
              {
                cities: [], country: 'Belgium'
              }
            ]
          )
        end
      end
    end
  end
end
