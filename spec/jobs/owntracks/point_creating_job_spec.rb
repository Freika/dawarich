# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Owntracks::PointCreatingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(point_params, user.id) }

    let(:point_params) do
      { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.now.to_i, topic: 'iPhone 12 pro' }
    end
    let(:user) { create(:user) }

    it 'creates a point' do
      expect { perform }.to change { Point.count }.by(1)
    end

    it 'creates a point with the correct user_id' do
      perform

      expect(Point.last.user_id).to eq(user.id)
    end

    context 'when point already exists' do
      it 'does not create a point' do
        perform

        expect { perform }.not_to(change { Point.count })
      end
    end
  end
end
