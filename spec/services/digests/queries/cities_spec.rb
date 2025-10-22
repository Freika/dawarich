# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Digests::Queries::Cities do
  let(:user) { create(:user) }
  let(:date_range) { Time.zone.parse('2024-12-01')..Time.zone.parse('2024-12-31').end_of_day }
  subject(:query) { described_class.new(user, date_range) }

  describe '#call' do
    context 'with no points' do
      it 'returns empty array' do
        result = query.call
        expect(result).to eq([])
      end
    end

    context 'with points in multiple cities' do
      let!(:points) do
        [
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-15 10:00').to_i, city: 'Berlin'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-15 14:00').to_i, city: 'Berlin'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-16 10:00').to_i, city: 'Hamburg'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-17 10:00').to_i, city: 'Berlin')
        ]
      end

      it 'returns cities sorted by visit count' do
        result = query.call

        expect(result).to be_an(Array)
        expect(result.first[:name]).to eq('Berlin')
        expect(result.first[:visits]).to eq(3)
        expect(result.second[:name]).to eq('Hamburg')
        expect(result.second[:visits]).to eq(1)
      end

      it 'respects the limit parameter' do
        limited_query = described_class.new(user, date_range, limit: 1)
        result = limited_query.call

        expect(result.length).to eq(1)
      end
    end
  end
end
