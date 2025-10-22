# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Digests::Calculator do
  let(:user) { create(:user) }
  let(:year) { 2024 }
  let(:month) { 12 }

  describe '#call' do
    context 'for monthly digest' do
      subject(:calculator) { described_class.new(user, period: :monthly, year: year, month: month) }

      it 'returns a hash with all required keys' do
        result = calculator.call

        expect(result).to be_a(Hash)
        expect(result.keys).to match_array(%i[
          period_type year month period_label overview distance_stats
          top_cities visited_places trips all_time_stats
        ])
      end

      it 'sets period_type to monthly' do
        result = calculator.call
        expect(result[:period_type]).to eq(:monthly)
      end

      it 'sets correct year and month' do
        result = calculator.call
        expect(result[:year]).to eq(year)
        expect(result[:month]).to eq(month)
      end

      it 'generates correct period_label' do
        result = calculator.call
        expect(result[:period_label]).to eq('December 2024')
      end

      context 'when error occurs' do
        before do
          allow_any_instance_of(Digests::Queries::Overview).to receive(:call).and_raise(StandardError, 'Test error')
        end

        it 'returns nil and logs error' do
          expect(calculator.call).to be_nil
        end
      end
    end

    context 'for yearly digest' do
      subject(:calculator) { described_class.new(user, period: :yearly, year: year) }

      it 'generates correct period_label' do
        result = calculator.call
        expect(result[:period_label]).to eq('2024')
      end

      it 'sets period_type to yearly' do
        result = calculator.call
        expect(result[:period_type]).to eq(:yearly)
      end
    end

    context 'with actual data' do
      let!(:points) do
        3.times.map do |i|
          create(:point,
                 user: user,
                 timestamp: Time.new(2024, 12, 15, 12, i).to_i,
                 city: 'Berlin',
                 country_name: 'Germany')
        end
      end

      subject(:calculator) { described_class.new(user, period: :monthly, year: year, month: month) }

      it 'includes overview data' do
        result = calculator.call
        expect(result[:overview]).to be_a(Hash)
        expect(result[:overview][:points_count]).to eq(3)
      end

      it 'includes distance stats' do
        result = calculator.call
        expect(result[:distance_stats]).to be_a(Hash)
        expect(result[:distance_stats]).to have_key(:total_distance_km)
      end

      it 'includes top cities' do
        result = calculator.call
        expect(result[:top_cities]).to be_an(Array)
      end

      it 'includes all time stats' do
        result = calculator.call
        expect(result[:all_time_stats]).to be_a(Hash)
        expect(result[:all_time_stats][:total_countries]).to be >= 0
      end
    end
  end
end
