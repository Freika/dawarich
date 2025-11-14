# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Digests::Queries::Overview do
  let(:user) { create(:user) }
  let(:date_range) { Time.zone.parse('2024-12-01')..Time.zone.parse('2024-12-31').end_of_day }
  subject(:query) { described_class.new(user, date_range) }

  describe '#call' do
    context 'with no data' do
      it 'returns zero counts' do
        result = query.call

        expect(result[:countries_count]).to eq(0)
        expect(result[:cities_count]).to eq(0)
        expect(result[:places_count]).to eq(0)
        expect(result[:points_count]).to eq(0)
      end
    end

    context 'with points in date range' do
      let!(:points_in_range) do
        [
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-15 12:00').to_i, city: 'Berlin', country_name: 'Germany'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-16 12:00').to_i, city: 'Hamburg', country_name: 'Germany'),
          create(:point, user: user, timestamp: Time.zone.parse('2024-12-17 12:00').to_i, city: 'Berlin', country_name: 'Germany')
        ]
      end

      let!(:points_outside_range) do
        create(:point, user: user, timestamp: Time.zone.parse('2024-11-15 12:00').to_i, city: 'Paris', country_name: 'France')
      end

      it 'counts only points in range' do
        result = query.call
        expect(result[:points_count]).to eq(3)
      end

      it 'counts distinct countries' do
        result = query.call
        expect(result[:countries_count]).to eq(1)
      end

      it 'counts distinct cities' do
        result = query.call
        expect(result[:cities_count]).to eq(2)
      end
    end

    context 'with visits and areas' do
      let(:area) { create(:area, user: user) }
      let!(:visit) do
        create(:visit,
               user: user,
               area: area,
               started_at: Time.zone.parse('2024-12-15 12:00'),
               ended_at: Time.zone.parse('2024-12-15 14:00'))
      end

      it 'counts places' do
        result = query.call
        expect(result[:places_count]).to eq(1)
      end
    end
  end
end
