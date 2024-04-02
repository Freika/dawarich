require 'rails_helper'

RSpec.describe Stat, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_presence_of(:year) }
    it { is_expected.to validate_presence_of(:month) }
  end

  describe 'methods' do
    let(:year) { 2021 }

    describe '.year_cities_and_countries' do
      subject { described_class.year_cities_and_countries(year) }

      before do
        stub_const('MINIMUM_POINTS_IN_CITY', 1)
      end

      context 'when there are points' do
        let!(:points) do
          create_list(:point, 3, city: 'City', country: 'Country', timestamp: DateTime.new(year, 1))
          create_list(:point, 2, city: 'Some City', country: 'Another country', timestamp: DateTime.new(year, 2))
        end


        it 'returns countries and cities' do
          expect(subject).to eq(countries: 2, cities: 2)
        end
      end

      context 'when there are no points' do
        it 'returns countries and cities' do
          expect(subject).to eq(countries: 0, cities: 0)
        end
      end
    end

    describe '.years' do
      subject { described_class.years }

      context 'when there are no stats' do
        it 'returns years' do
          expect(subject).to eq([Time.current.year])
        end
      end

      context 'when there are stats' do
        let(:user) { create(:user) }
        let(:expected_years) { (year..Time.current.year).to_a.reverse }

        before do
          create(:stat, year: 2021, user: user)
          create(:stat, year: 2020, user: user)
        end

        it 'returns years' do
          expect(subject).to eq(expected_years)
        end
      end
    end

    describe '#distance_by_day' do
      subject { stat.distance_by_day }

      let(:user) { create(:user) }
      let(:stat) { create(:stat, year: year, month: 1, user: user) }
      let(:expected_distance) do
        # 31 day of January
        (1..31).map { |day| [day, 0] }
      end

      context 'when there are points' do
        let!(:points) do
          create(:point, latitude: 1, longitude: 1, timestamp: DateTime.new(year, 1, 1, 1))
          create(:point, latitude: 2, longitude: 2, timestamp: DateTime.new(year, 1, 1, 2))
        end

        before { expected_distance[0][1] = 157.23 }

        it 'returns distance by day' do
          expect(subject).to eq(expected_distance)
        end
      end

      context 'when there are no points' do
        it 'returns distance by day' do
          expect(subject).to eq(expected_distance)
        end
      end
    end

    describe '#timespan' do
      subject { stat.send(:timespan) }

      let(:stat) { build(:stat, year: year, month: 1) }
      let(:expected_timespan) { DateTime.new(year, 1).beginning_of_month..DateTime.new(year, 1).end_of_month }

      it 'returns timespan' do
        expect(subject).to eq(expected_timespan)
      end
    end

    describe '#self.year_distance' do
      subject { described_class.year_distance(year) }

      let(:user) { create(:user) }
      let(:expected_distance) do
        (1..12).map { |month| [Date::MONTHNAMES[month], 0] }
      end

      context 'when there are stats' do
        let!(:stats) do
          create(:stat, year: year, month: 1, distance: 100, user: user)
          create(:stat, year: year, month: 2, distance: 200, user: user)
        end

        before do
          expected_distance[0][1] = 100
          expected_distance[1][1] = 200
        end

        it 'returns year distance' do
          expect(subject).to eq(expected_distance)
        end
      end

      context 'when there are no stats' do
        it 'returns year distance' do
          expect(subject).to eq(expected_distance)
        end
      end
    end
  end
end
