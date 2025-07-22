# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatsQuery do
  describe '#points_stats' do
    subject(:points_stats) { described_class.new(user).points_stats }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user: user) }

    context 'when user has no points' do
      it 'returns zero counts for all statistics' do
        expect(points_stats).to eq({
          total: 0,
          geocoded: 0,
          without_data: 0
        })
      end
    end

    context 'when user has points' do
      let!(:geocoded_point_with_data) do
        create(:point,
               user: user,
               import: import,
               reverse_geocoded_at: Time.current,
               geodata: { 'address' => '123 Main St' })
      end

      let!(:geocoded_point_without_data) do
        create(:point,
               user: user,
               import: import,
               reverse_geocoded_at: Time.current,
               geodata: {})
      end

      let!(:non_geocoded_point) do
        create(:point,
               user: user,
               import: import,
               reverse_geocoded_at: nil,
               geodata: { 'some' => 'data' })
      end

      it 'returns correct counts for all statistics' do
        expect(points_stats).to eq({
          total: 3,
          geocoded: 2,
          without_data: 1
        })
      end

      context 'when another user has points' do
        let(:other_user) { create(:user) }
        let!(:other_import) { create(:import, user: other_user) }
        let!(:other_point) do
          create(:point,
                 user: other_user,
                 import: other_import,
                 reverse_geocoded_at: Time.current,
                 geodata: { 'address' => 'Other Address' })
        end

        it 'only counts points for the specified user' do
          expect(points_stats).to eq({
            total: 3,
            geocoded: 2,
            without_data: 1
          })
        end
      end
    end

    context 'when all points are geocoded with data' do
      before do
        create_list(:point, 5,
                    user: user,
                    import: import,
                    reverse_geocoded_at: Time.current,
                    geodata: { 'address' => 'Some Address' })
      end

      it 'returns correct statistics' do
        expect(points_stats).to eq({
          total: 5,
          geocoded: 5,
          without_data: 0
        })
      end
    end

    context 'when all points are without geodata' do
      before do
        create_list(:point, 3,
                    user: user,
                    import: import,
                    reverse_geocoded_at: Time.current,
                    geodata: {})
      end

      it 'returns correct statistics' do
        expect(points_stats).to eq({
          total: 3,
          geocoded: 3,
          without_data: 3
        })
      end
    end

    context 'when all points are not geocoded' do
      before do
        create_list(:point, 4,
                    user: user,
                    import: import,
                    reverse_geocoded_at: nil,
                    geodata: { 'some' => 'data' })
      end

      it 'returns correct statistics' do
        expect(points_stats).to eq({
          total: 4,
          geocoded: 0,
          without_data: 0
        })
      end
    end
  end
end