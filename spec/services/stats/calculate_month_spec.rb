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
               latitude: 52.107902115161316,
               longitude: 14.452712811406352)
      end
      let!(:point2) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp2,
               latitude: 51.9746598171507,
               longitude: 12.291519487061901)
      end
      let!(:point3) do
        create(:point,
               user:,
               import:,
               timestamp: timestamp3,
               latitude: 52.72859111523629,
               longitude: 9.77973105800526)
      end

      context 'when units are kilometers' do
        before { stub_const('DISTANCE_UNIT', :km) }

        it 'creates stats' do
          expect { calculate_stats }.to change { Stat.count }.by(1)
        end

        it 'calculates distance' do
          calculate_stats

          expect(user.stats.last.distance).to eq(338)
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

      context 'when units are miles' do
        before { stub_const('DISTANCE_UNIT', :mi) }

        it 'creates stats' do
          expect { calculate_stats }.to change { Stat.count }.by(1)
        end

        it 'calculates distance' do
          calculate_stats

          expect(user.stats.last.distance).to eq(210)
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
    end
  end
end
