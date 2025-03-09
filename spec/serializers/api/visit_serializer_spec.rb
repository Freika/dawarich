# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::VisitSerializer do
  describe '#call' do
    let(:place) do
      instance_double(
        Place,
        id: 123,
        lat: 40.7812,
        lon: -73.9665
      )
    end

    let(:area) do
      instance_double(
        Area,
        id: 456,
        latitude: 41.9028,
        longitude: -87.6350
      )
    end

    let(:visit) do
      instance_double(
        Visit,
        id: 789,
        area_id: area.id,
        user_id: 101,
        started_at: Time.zone.parse('2023-01-15T10:00:00Z'),
        ended_at: Time.zone.parse('2023-01-15T12:00:00Z'),
        duration: 120, # 2 hours in minutes
        name: 'Central Park Visit',
        status: 'confirmed',
        place: place,
        area: area,
        place_id: place.id
      )
    end

    subject(:serializer) { described_class.new(visit) }

    context 'when a visit has both place and area' do
      it 'serializes the visit with place coordinates' do
        result = serializer.call

        expect(result).to be_a(Hash)
        expect(result[:id]).to eq(789)
        expect(result[:area_id]).to eq(456)
        expect(result[:user_id]).to eq(101)
        expect(result[:started_at]).to eq(Time.zone.parse('2023-01-15T10:00:00Z'))
        expect(result[:ended_at]).to eq(Time.zone.parse('2023-01-15T12:00:00Z'))
        expect(result[:duration]).to eq(120)
        expect(result[:name]).to eq('Central Park Visit')
        expect(result[:status]).to eq('confirmed')

        # Place should use place coordinates
        expect(result[:place][:id]).to eq(123)
        expect(result[:place][:latitude]).to eq(40.7812)
        expect(result[:place][:longitude]).to eq(-73.9665)
      end
    end

    context 'when a visit has area but no place' do
      let(:visit_without_place) do
        instance_double(
          Visit,
          id: 789,
          area_id: area.id,
          user_id: 101,
          started_at: Time.zone.parse('2023-01-15T10:00:00Z'),
          ended_at: Time.zone.parse('2023-01-15T12:00:00Z'),
          duration: 120,
          name: 'Chicago Visit',
          status: 'suggested',
          place: nil,
          area: area,
          place_id: nil
        )
      end

      subject(:serializer_without_place) { described_class.new(visit_without_place) }

      it 'falls back to area coordinates' do
        result = serializer_without_place.call

        expect(result[:place][:id]).to be_nil
        expect(result[:place][:latitude]).to eq(41.9028)
        expect(result[:place][:longitude]).to eq(-87.6350)
      end
    end

    context 'when a visit has neither place nor area' do
      let(:visit_without_location) do
        instance_double(
          Visit,
          id: 789,
          area_id: nil,
          user_id: 101,
          started_at: Time.zone.parse('2023-01-15T10:00:00Z'),
          ended_at: Time.zone.parse('2023-01-15T12:00:00Z'),
          duration: 120,
          name: 'Unknown Location Visit',
          status: 'declined',
          place: nil,
          area: nil,
          place_id: nil
        )
      end

      subject(:serializer_without_location) { described_class.new(visit_without_location) }

      it 'returns nil for location coordinates' do
        result = serializer_without_location.call

        expect(result[:place][:id]).to be_nil
        expect(result[:place][:latitude]).to be_nil
        expect(result[:place][:longitude]).to be_nil
      end
    end

    context 'with actual Visit model', type: :model do
      let(:real_place) { create(:place) }
      let(:real_area) { create(:area) }
      let(:real_visit) { create(:visit, place: real_place, area: real_area) }

      subject(:real_serializer) { described_class.new(real_visit) }

      it 'serializes a real visit model correctly' do
        result = real_serializer.call

        expect(result[:id]).to eq(real_visit.id)
        expect(result[:area_id]).to eq(real_visit.area_id)
        expect(result[:user_id]).to eq(real_visit.user_id)
        expect(result[:started_at]).to eq(real_visit.started_at)
        expect(result[:ended_at]).to eq(real_visit.ended_at)
        expect(result[:duration]).to eq(real_visit.duration)
        expect(result[:name]).to eq(real_visit.name)
        expect(result[:status]).to eq(real_visit.status)

        expect(result[:place][:id]).to eq(real_place.id)
        expect(result[:place][:latitude]).to eq(real_place.lat)
        expect(result[:place][:longitude]).to eq(real_place.lon)
      end
    end
  end
end
