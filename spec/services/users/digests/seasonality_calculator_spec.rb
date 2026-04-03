# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::SeasonalityCalculator do
  describe '#call' do
    subject(:result) { described_class.new(user, year).call }

    let(:year) { 2024 }

    context 'with a Northern Hemisphere user (Europe/London)' do
      let(:user) { create(:user, settings: { 'timezone' => 'Europe/London' }) }

      context 'when the user has no stats' do
        it 'returns zeroed seasonality' do
          expect(result).to eq({ 'winter' => 0, 'spring' => 0, 'summer' => 0, 'fall' => 0 })
        end
      end

      context 'when stats exist across months' do
        before do
          # Summer months (NH): June, July, August
          create(:stat, user: user, year: year, month: 6,  distance: 300)
          create(:stat, user: user, year: year, month: 7,  distance: 300)
          create(:stat, user: user, year: year, month: 8,  distance: 400)
          # Winter months (NH): December, January, February
          create(:stat, user: user, year: year, month: 12, distance: 500)
          create(:stat, user: user, year: year, month: 1,  distance: 200)
        end

        it 'assigns June–August distance to summer' do
          expect(result['summer']).to eq(59) # (1000 / 1700.0 * 100).round
        end

        it 'assigns December–January distance to winter' do
          expect(result['winter']).to eq(41) # (700 / 1700.0 * 100).round
        end

        it 'assigns zero to untravelled seasons' do
          expect(result['spring']).to eq(0)
          expect(result['fall']).to eq(0)
        end

        it 'percentages sum to 100' do
          expect(result.values.sum).to eq(100)
        end
      end
    end

    context 'with a Southern Hemisphere user (Australia/Sydney)' do
      let(:user) { create(:user, settings: { 'timezone' => 'Australia/Sydney' }) }

      context 'when stats exist across months' do
        before do
          # June–August are WINTER in SH
          create(:stat, user: user, year: year, month: 6,  distance: 500)
          create(:stat, user: user, year: year, month: 7,  distance: 500)
          # December–February are SUMMER in SH
          create(:stat, user: user, year: year, month: 12, distance: 1000)
        end

        it 'maps June–August to winter (SH)' do
          expect(result['winter']).to eq(50) # 1000 / 2000 * 100
        end

        it 'maps December to summer (SH)' do
          expect(result['summer']).to eq(50) # 1000 / 2000 * 100
        end

        it 'assigns zero to untravelled seasons' do
          expect(result['spring']).to eq(0)
          expect(result['fall']).to eq(0)
        end
      end

      context 'when the same months would be labelled differently for a NH user' do
        before do
          # March–May are FALL in SH (not spring as in NH)
          create(:stat, user: user, year: year, month: 3, distance: 1000)
        end

        it 'labels March as fall, not spring' do
          expect(result['fall']).to eq(100)
          expect(result['spring']).to eq(0)
        end
      end
    end

    context 'when the user has no timezone set' do
      let(:user) { create(:user, settings: {}) }

      it 'defaults to Northern Hemisphere season mapping' do
        create(:stat, user: user, year: year, month: 7, distance: 1000)

        expect(result['summer']).to eq(100)
      end
    end
  end
end
