# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateStats do
  describe '#call' do
    subject(:create_stats) { described_class.new(user_ids).call }

    let(:user_ids) { [user.id] }
    let(:user) { create(:user) }

    context 'when there are no points' do
      it 'does not create stats' do
        expect { create_stats }.not_to(change { Stat.count })
      end
    end

    context 'when there are points' do
      let!(:import) { create(:import, user:) }
      let!(:point1) { create(:point, user:, import:, latitude: 0, longitude: 0) }
      let!(:point2) { create(:point, user:, import:, latitude: 1, longitude: 2) }
      let!(:point3) { create(:point, user:, import:, latitude: 3, longitude: 4) }

      it 'creates stats' do
        expect { create_stats }.to change { Stat.count }.by(1)
      end

      it 'calculates distance' do
        create_stats

        expect(Stat.last.distance).to eq(563)
      end

      it 'created notifications' do
        expect { create_stats }.to change { Notification.count }.by(1)
      end

      context 'when there is an error' do
        before do
          allow(Stat).to receive(:find_or_initialize_by).and_raise(StandardError)
        end

        it 'does not create stats' do
          expect { create_stats }.not_to(change { Stat.count })
        end

        it 'created notifications' do
          expect { create_stats }.to change { Notification.count }.by(1)
        end
      end
    end
  end
end
