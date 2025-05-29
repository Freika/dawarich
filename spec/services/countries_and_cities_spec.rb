# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call' do
    subject(:countries_and_cities) { described_class.new(points).call }

    # Test with a set of points in the same city (Kerpen) but different countries,
    # with sufficient points to demonstrate the city grouping logic
    let(:timestamp) { DateTime.new(2021, 1, 1, 0, 0, 0) }

    let(:points) do
      [
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp:),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 10.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 20.minutes),
        create(:point, city: 'Kerpen', country: 'Germany', timestamp: timestamp + 30.minutes),
        create(:point, city: 'Kerpen', country: 'Germany', timestamp: timestamp + 40.minutes),
        create(:point, city: 'Kerpen', country: 'Germany', timestamp: timestamp + 50.minutes),
        create(:point, city: 'Kerpen', country: 'Germany', timestamp: timestamp + 60.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 70.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 80.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 90.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 100.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 110.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 120.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 130.minutes),
        create(:point, city: 'Kerpen', country: 'Belgium', timestamp: timestamp + 140.minutes)
      ]
    end

    context 'when MIN_MINUTES_SPENT_IN_CITY is 60 (in minutes)' do
      before do
        stub_const('MIN_MINUTES_SPENT_IN_CITY', 60)
      end

      context 'when user stayed in the city for more than 1 hour' do
        it 'returns countries and cities' do
          # Only Belgium has cities where the user stayed long enough
          # Germany is excluded because the consecutive points in Kerpen, Germany
          # span only 30 minutes (less than MIN_MINUTES_SPENT_IN_CITY)
          expect(countries_and_cities).to contain_exactly(
            an_object_having_attributes(
              country: 'Belgium',
              cities: contain_exactly(
                an_object_having_attributes(
                  city: 'Kerpen',
                  points: 11,
                  stayed_for: 140
                )
              )
            )
          )
        end
      end

      context 'when user stayed in the city for less than 1 hour in some cities but more in others' do
        let(:points) do
          [
            create(:point, city: 'Berlin', country: 'Germany', timestamp:),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 10.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 20.minutes),
            create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 80.minutes),
            create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 90.minutes),
            create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + 100.minutes),
            create(:point, city: 'Brugges', country: 'Belgium', timestamp: timestamp + 110.minutes)
          ]
        end

        it 'returns only countries with cities where the user stayed long enough' do
          # Only Germany is included because Berlin points span 100 minutes
          # Belgium is excluded because Brugges points are in separate visits
          # spanning only 10 and 20 minutes each
          expect(countries_and_cities).to contain_exactly(
            an_object_having_attributes(
              country: 'Germany',
              cities: contain_exactly(
                an_object_having_attributes(
                  city: 'Berlin',
                  points: 4,
                  stayed_for: 100
                )
              )
            )
          )
        end
      end
    end
  end
end
