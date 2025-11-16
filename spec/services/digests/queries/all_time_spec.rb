# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Digests::Queries::AllTime do
  let(:user) { create(:user) }
  subject(:query) { described_class.new(user) }

  describe '#call' do
    context 'with no data' do
      it 'returns zero counts' do
        result = query.call

        expect(result[:total_countries]).to eq(0)
        expect(result[:total_cities]).to eq(0)
        expect(result[:total_places]).to eq(0)
        expect(result[:total_distance_km]).to eq(0)
        expect(result[:first_point_date]).to be_nil
      end

      it 'calculates account age' do
        result = query.call
        expect(result[:account_age_days]).to be >= 0
      end
    end

    context 'with data' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: Time.zone.parse('2024-01-15 10:00').to_i, city: 'Berlin', country_name: 'Germany'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-06-15 10:00').to_i, city: 'Paris', country_name: 'France')
        ]
      end

      let!(:stat) { create(:stat, user: user, year: 2024, month: 1, distance: 100) }

      it 'counts total countries' do
        result = query.call
        expect(result[:total_countries]).to eq(2)
      end

      it 'counts total cities' do
        result = query.call
        expect(result[:total_cities]).to eq(2)
      end

      it 'sums distance from stats' do
        result = query.call
        expect(result[:total_distance_km]).to eq(100)
      end

      it 'finds first point date' do
        result = query.call
        expect(result[:first_point_date]).to eq(Date.new(2024, 1, 15))
      end
    end
  end
end
