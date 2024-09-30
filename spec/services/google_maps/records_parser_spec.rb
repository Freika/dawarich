# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::RecordsParser do
  describe '#call' do
    subject(:parser) { described_class.new(import).call(json) }

    let(:import) { create(:import) }
    let(:json) do
      {
        'latitudeE7' => 123_456_789,
        'longitudeE7' => 123_456_789,
        'timestamp' => Time.zone.now.to_s,
        'altitude' => 0,
        'velocity' => 0
      }
    end

    it 'creates a point' do
      expect { parser }.to change(Point, :count).by(1)
    end

    context 'when point already exists' do
      before do
        create(
          :point, user: import.user, import:, latitude: 12.3456789, longitude: 12.3456789,
          timestamp: Time.zone.now.to_i
        )
      end

      it 'does not create a point' do
        expect { parser }.not_to change(Point, :count)
      end
    end
  end
end
