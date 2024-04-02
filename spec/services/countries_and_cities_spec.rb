require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call' do
    subject(:countries_and_cities) { described_class.new(points).call }

    let(:points) do
      [
        create(:point, latitude: 0, longitude: 0, city: 'City', country: 'Country'),
        create(:point, latitude: 1, longitude: 1, city: 'City', country: 'Country'),
        create(:point, latitude: 2, longitude: 2, city: 'City', country: 'Country'),
        create(:point, latitude: 2, longitude: 2, city: 'Another city', country: 'Some Country'),
        create(:point, latitude: 2, longitude: 6, city: 'Another city', country: 'Some Country')
      ]
    end

    context 'when MINIMUM_POINTS_IN_CITY is 1' do
      before do
        stub_const('CountriesAndCities::MINIMUM_POINTS_IN_CITY', 1)
      end

      it 'returns countries and cities' do
        expect(countries_and_cities).to eq(
          [
            { cities: [{city: "City", points: 3, timestamp: 1}], country: "Country" },
            { cities: [{city: "Another city", points: 2, timestamp: 1}], country: "Some Country" }
          ]
        )
      end
    end

    context 'when MINIMUM_POINTS_IN_CITY is 3' do
      before do
        stub_const('CountriesAndCities::MINIMUM_POINTS_IN_CITY', 3)
      end

      it 'returns countries and cities' do
        expect(countries_and_cities).to eq(
          [
            { cities: [{city: "City", points: 3, timestamp: 1}], country: "Country" },
            { cities: [], country: "Some Country" }
          ]
        )
      end
    end
  end
end
