# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::CalculateMonth do
  describe '#call' do
    subject(:calculate_stats) { described_class.new(user.id, year, month).call }

    let(:user) { create(:user) }
    let(:year) { 2021 }
    let(:month) { 1 }

    context 'when there are no points' do
      it 'does not create stats' do
        expect { calculate_stats }.not_to(change { Stat.count })
      end

      context 'when stats already exist for the month' do
        before do
          create(:stat, user: user, year: year, month: month)
        end

        it 'deletes existing stats for that month' do
          expect { calculate_stats }.to change { Stat.count }.by(-1)
        end
      end
    end

    context 'when there are points' do
      let(:timestamp1) { DateTime.new(year, month, 1, 12).to_i }
      let(:timestamp2) { DateTime.new(year, month, 1, 13).to_i }
      let(:timestamp3) { DateTime.new(year, month, 1, 14).to_i }
      let!(:import) { create(:import, user:) }
      let!(:point1) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp1,
               lonlat: 'POINT(14.452712811406352 52.107902115161316)')
      end
      let!(:point2) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp2,
               lonlat: 'POINT(12.291519487061901 51.9746598171507)')
      end
      let!(:point3) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp3,
               lonlat: 'POINT(9.77973105800526 52.72859111523629)')
      end

      context 'when calculating distance' do
        it 'creates stats' do
          expect { calculate_stats }.to change { Stat.count }.by(1)
        end

        it 'calculates distance in meters consistently' do
          calculate_stats

          # Distance should be calculated in meters regardless of user unit preference
          # The actual distance between the test points is approximately 340 km = 340,000 meters
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end

        context 'when there is an error' do
          before do
            allow(Stat).to receive(:find_or_initialize_by).and_raise(StandardError)
          end

          it 'does not create stats' do
            expect { calculate_stats }.not_to(change { Stat.count })
          end

          it 'creates a notification' do
            expect { calculate_stats }.to change { Notification.count }.by(1)
          end
        end
      end

      context 'when user prefers miles' do
        before do
          user.update(settings: { maps: { distance_unit: 'mi' } })
        end

        it 'still stores distance in meters (same as km users)' do
          calculate_stats

          # Distance stored should be the same regardless of user preference (meters)
          expect(user.stats.last.distance).to be_within(1000).of(340_000)
        end
      end
    end
  end
end
