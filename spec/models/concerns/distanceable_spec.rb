# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Distanceable, type: :model do
  let(:user) { create(:user) }

  # Berlin to Potsdam: roughly 26-27 km apart
  let!(:point1) do
    create(
      :point,
      user: user,
      timestamp: 1.hour.ago.to_i,
      lonlat: 'POINT(13.404954 52.520008)'
    )
  end
  let!(:point2) do
    create(
      :point,
      user: user,
      timestamp: 30.minutes.ago.to_i,
      lonlat: 'POINT(13.064477 52.398862)'
    )
  end

  describe '.total_distance' do
    context 'when given an ActiveRecord::Relation' do
      it 'calculates the total distance in km by default' do
        distance = Point.total_distance(Point.where(id: [point1.id, point2.id]))
        expect(distance).to be_within(1.0).of(27.0)
      end

      it 'calculates the total distance in meters when requested' do
        distance = Point.total_distance(Point.where(id: [point1.id, point2.id]), :m)
        expect(distance).to be_within(1000.0).of(27_000.0)
      end

      it 'returns 0 for an empty relation' do
        distance = Point.total_distance(Point.none)
        expect(distance).to eq(0)
      end

      it 'returns 0 for a relation with a single point' do
        distance = Point.total_distance(Point.where(id: point1.id))
        expect(distance).to eq(0)
      end

      it 'calculates distance via SQL without loading records into memory' do
        relation = Point.where(id: [point1.id, point2.id])
        expect(relation).not_to receive(:to_a)
        Point.total_distance(relation)
      end
    end

    context 'when called on a scoped relation' do
      it 'calculates distance without arguments' do
        distance = user.points.total_distance
        expect(distance).to be_within(1.0).of(27.0)
      end

      it 'accepts unit as first argument when called on a relation' do
        distance = user.points.total_distance(:m)
        expect(distance).to be_within(1000.0).of(27_000.0)
      end

      it 'accepts nil as points and unit as second argument' do
        distance = user.points.total_distance(nil, :m)
        expect(distance).to be_within(1000.0).of(27_000.0)
      end
    end

    context 'when given an Array of points' do
      it 'calculates the total distance in km' do
        distance = Point.total_distance([point1, point2], :km)
        expect(distance).to be_within(1.0).of(27.0)
      end

      it 'returns 0 for an empty array' do
        expect(Point.total_distance([], :km)).to eq(0)
      end

      it 'returns 0 for an array with a single point' do
        expect(Point.total_distance([point1], :km)).to eq(0)
      end
    end

    context 'with invalid units' do
      it 'raises ArgumentError' do
        expect { Point.total_distance(Point.where(id: [point1.id, point2.id]), :light_years) }
          .to raise_error(ArgumentError, /Invalid unit/)
      end
    end
  end
end
