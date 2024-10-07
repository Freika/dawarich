# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:expected_json) { point.attributes.except(*Api::PointSerializer::EXCLUDED_ATTRIBUTES) }

    it 'returns JSON with correct attributes' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end

    it 'does not include excluded attributes' do
      expect(serializer).not_to include(*Api::PointSerializer::EXCLUDED_ATTRIBUTES)
    end
  end
end
