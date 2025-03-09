# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::VisitSerializer do
  describe '#call' do
    let(:place) { create(:place) }
    let(:area) { create(:area) }
    let(:visit) { create(:visit, place: place, area: area) }

    subject(:serializer) { described_class.new(visit) }

    it 'serializes a real visit model correctly' do
      result = serializer.call

      expect(result[:id]).to eq(visit.id)
      expect(result[:area_id]).to eq(visit.area_id)
      expect(result[:user_id]).to eq(visit.user_id)
      expect(result[:started_at]).to eq(visit.started_at)
      expect(result[:ended_at]).to eq(visit.ended_at)
      expect(result[:duration]).to eq(visit.duration)
      expect(result[:name]).to eq(visit.name)
      expect(result[:status]).to eq(visit.status)

      expect(result[:place][:id]).to eq(place.id)
      expect(result[:place][:latitude]).to eq(place.lat)
      expect(result[:place][:longitude]).to eq(place.lon)
    end
  end
end
