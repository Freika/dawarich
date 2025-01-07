# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stat, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_presence_of(:year) }
    it { is_expected.to validate_presence_of(:month) }
  end

  describe 'methods' do
    let(:year) { 2021 }
    let(:user) { create(:user) }

    describe '#distance_by_day' do
      subject { stat.distance_by_day }

      let(:user) { create(:user) }
      let(:stat) { create(:stat, year:, month: 1, user:) }
      let(:expected_distance) do
        # 31 day of January
        (1..31).map { |day| [day, 0] }
      end

      context 'when there are points' do
        let!(:points) do
          create(:point, user:, latitude: 1, longitude: 1, timestamp: DateTime.new(year, 1, 1, 1))
          create(:point, user:, latitude: 2, longitude: 2, timestamp: DateTime.new(year, 1, 1, 2))
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

      let(:stat) { build(:stat, year:, month: 1) }
      let(:expected_timespan) { DateTime.new(year, 1).beginning_of_month..DateTime.new(year, 1).end_of_month }

      it 'returns timespan' do
        expect(subject).to eq(expected_timespan)
      end
    end

    describe '#self.year_distance' do
      subject { described_class.year_distance(year, user) }

      let(:user) { create(:user) }
      let(:expected_distance) do
        (1..12).map { |month| [Date::MONTHNAMES[month], 0] }
      end

      context 'when there are stats' do
        let!(:stats) do
          create(:stat, year:, month: 1, distance: 100, user:)
          create(:stat, year:, month: 2, distance: 200, user:)
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

    describe '#points' do
      subject { stat.points.to_a }

      let(:stat) { create(:stat, year:, month: 1, user:) }
      let(:timestamp) { DateTime.new(year, 1, 1, 5, 0, 0) }
      let!(:points) { create_list(:point, 3, user:, timestamp:) }

      it 'returns points' do
        expect(subject).to eq(points)
      end
    end
  end
end
