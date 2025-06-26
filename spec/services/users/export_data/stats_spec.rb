# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Stats, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#call' do
    context 'when user has no stats' do
      it 'returns an empty array' do
        result = service.call
        expect(result).to eq([])
      end
    end

    context 'when user has stats' do
      let!(:stat1) { create(:stat, user: user, year: 2024, month: 1, distance: 100) }
      let!(:stat2) { create(:stat, user: user, year: 2024, month: 2, distance: 150) }

      it 'returns all user stats' do
        result = service.call
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
      end

      it 'excludes user_id and id fields' do
        result = service.call

        result.each do |stat_data|
          expect(stat_data).not_to have_key('user_id')
          expect(stat_data).not_to have_key('id')
        end
      end

      it 'includes expected stat attributes' do
        result = service.call
        stat_data = result.find { |s| s['month'] == 1 }

        expect(stat_data).to include(
          'year' => 2024,
          'month' => 1,
          'distance' => 100
        )
        expect(stat_data).to have_key('created_at')
        expect(stat_data).to have_key('updated_at')
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_stat) { create(:stat, user: user, year: 2024, month: 1) }
      let!(:other_user_stat) { create(:stat, user: other_user, year: 2024, month: 1) }

      it 'only returns stats for the specified user' do
        result = service.call
        expect(result.size).to eq(1)
      end
    end
  end
end
