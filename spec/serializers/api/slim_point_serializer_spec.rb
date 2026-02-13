# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::SlimPointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let!(:point) { create(:point, :with_known_location) }
    let(:expected_json) do
      {
        id:           point.id,
        latitude:     point.lat.to_s,
        longitude:    point.lon.to_s,
        timestamp:    point.timestamp,
        velocity:     point.velocity,
        country_name: point.country_name
      }
    end

    it 'returns JSON with correct attributes' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end
  end
end
