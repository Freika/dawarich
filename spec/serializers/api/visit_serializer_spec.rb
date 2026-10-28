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
      expect(result[:display_name]).to eq(visit.name)
      expect(result[:place_id]).to eq(place.id)
      expect(result[:status]).to eq(visit.status)

      expect(result[:place][:id]).to eq(place.id)
      expect(result[:place][:latitude]).to eq(place.lat)
      expect(result[:place][:longitude]).to eq(place.lon)
      expect(result[:place][:visit_radius]).to eq(place.visit_radius)
    end

    it 'falls back to the Area geometry for an Area-only Visit awaiting migration' do
      area = create(:area, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 120)
      area_only = create(:visit, user: area.user, area: area, place: nil)

      expect(described_class.new(area_only).call[:place]).to eq(
        id: nil, name: 'Home', latitude: 52.5, longitude: 13.4, visit_radius: 120
      )
    end

    it 'keeps reporting the legacy Area ID after the Visit moves to the mapped Place' do
      area = create(:area)
      mapped = create(:place, user: area.user)
      LegacyAreaPlaceMapping.create!(area: area, place: mapped)
      migrated = create(:visit, user: area.user, place: mapped)

      expect(described_class.new(migrated).call[:area_id]).to eq(area.id)
    end

    context 'confidence fields' do
      it 'exposes confidence and confidence_band when set' do
        visit.update!(confidence: 85)

        result = described_class.new(visit.reload).call

        expect(result[:confidence]).to eq(85)
        expect(result[:confidence_band]).to eq(:high)
      end

      it 'is null-safe when confidence is nil' do
        visit.update!(confidence: nil)

        result = described_class.new(visit.reload).call

        expect(result[:confidence]).to be_nil
        expect(result[:confidence_band]).to be_nil
      end
    end
  end
end
