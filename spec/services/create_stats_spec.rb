require 'rails_helper'

RSpec.describe CreateStats do
  describe '#call' do
    subject(:create_stats) { described_class.new(user_ids).call }

    let(:user_ids) { [user.id] }
    let(:user) { create(:user) }

    context 'when there are no points' do
      it 'does not create stats' do
        expect { create_stats }.not_to change { Stat.count }
      end
    end

    context 'when there are points' do
      let!(:import) { create(:import, user: user) }
      let!(:point_1) { create(:point, import: import, latitude: 0, longitude: 0) }
      let!(:point_2) { create(:point, import: import, latitude: 1, longitude: 2) }
      let!(:point_3) { create(:point, import: import, latitude: 3, longitude: 4) }


      it 'creates stats' do
        expect { create_stats }.to change { Stat.count }.by(1)
      end

      it 'calculates distance' do
        create_stats

        expect(Stat.last.distance).to eq(563)
      end
    end
  end
end
