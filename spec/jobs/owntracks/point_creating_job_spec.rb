require 'rails_helper'

RSpec.describe Owntracks::PointCreatingJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(point_params) }

    let(:point_params) do
      { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.now.to_i, topic: 'iPhone 12 pro' }
    end

    it 'creates a point' do
      expect { perform }.to change { Point.count }.by(1)
    end
  end
end
