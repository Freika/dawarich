# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Digests::Queries::Distance do
  let(:user) { create(:user) }
  let(:date_range) { Time.zone.parse('2024-12-01')..Time.zone.parse('2024-12-31').end_of_day }
  subject(:query) { described_class.new(user, date_range) }

  describe '#call' do
    context 'with no points' do
      it 'returns zero distance' do
        result = query.call

        expect(result[:total_distance_km]).to eq(0)
        expect(result[:daily_average_km]).to eq(0)
        expect(result[:max_distance_day]).to be_nil
      end
    end

    context 'with points' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-15 10:00').to_i, latitude: 52.52, longitude: 13.405),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-15 14:00').to_i, latitude: 52.51, longitude: 13.395),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-16 10:00').to_i, latitude: 52.50, longitude: 13.385)
        ]
      end

      it 'calculates total distance' do
        result = query.call
        expect(result[:total_distance_km]).to be > 0
      end

      it 'calculates daily average' do
        result = query.call
        expect(result[:daily_average_km]).to be >= 0
      end

      it 'finds max distance day' do
        result = query.call
        expect(result[:max_distance_day]).to be_a(Hash)
        expect(result[:max_distance_day][:date]).to be_a(Date)
        expect(result[:max_distance_day][:distance_km]).to be > 0
      end
    end
  end
end
