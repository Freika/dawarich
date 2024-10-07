# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::SlimPointSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(point).call }

    let(:point) { create(:point) }
    let(:expected_json) { point.attributes.slice('id', 'latitude', 'longitude', 'timestamp') }

    it 'returns JSON with correct attributes' do
      expect(serializer.to_json).to eq(expected_json.to_json)
    end
  end
end
