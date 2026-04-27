# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Gapfill::PointGenerator do
  let(:user) { create(:user) }
  let(:start_point) do
    create(:point, user: user, lonlat: 'POINT(13.3888 52.5170)', timestamp: 1_000_000)
  end
  let(:end_point) do
    create(:point, user: user, lonlat: 'POINT(13.4050 52.5200)', timestamp: 1_001_000)
  end

  let(:coordinates) do
    [
      [13.3888, 52.5170], # start (will be skipped)
      [13.3920, 52.5180],
      [13.3950, 52.5185],
      [13.3980, 52.5190],
      [13.4050, 52.5200]  # end (will be skipped)
    ]
  end

  subject(:generator) do
    described_class.new(
      coordinates: coordinates,
      start_point: start_point,
      end_point: end_point,
      user: user
    )
  end

  describe '#build_points' do
    it 'returns the correct number of points (coordinates minus the two endpoints)' do
      points = generator.build_points
      expect(points.size).to eq(3)
    end

    it 'sets source to inferred on all generated points' do
      points = generator.build_points
      expect(points).to all(have_attributes(source: 'inferred'))
    end

    it 'assigns points to the correct user' do
      points = generator.build_points
      expect(points).to all(have_attributes(user: user))
    end

    it 'generates timestamps that strictly increase' do
      points = generator.build_points
      timestamps = points.map(&:timestamp)
      expect(timestamps).to eq(timestamps.sort)
      expect(timestamps.uniq.size).to eq(timestamps.size)
    end

    it 'generates timestamps between the start and end timestamps' do
      points = generator.build_points
      points.each do |point|
        expect(point.timestamp).to be > start_point.timestamp
        expect(point.timestamp).to be < end_point.timestamp
      end
    end

    it 'returns unsaved records' do
      points = generator.build_points
      expect(points).to all(be_new_record)
    end

    context 'when coordinates have only two points (the endpoints)' do
      let(:coordinates) { [[13.3888, 52.5170], [13.4050, 52.5200]] }

      it 'returns an empty array' do
        expect(generator.build_points).to eq([])
      end
    end

    context 'when coordinates have a single intermediate point' do
      let(:coordinates) do
        [
          [13.3888, 52.5170],
          [13.3950, 52.5185],
          [13.4050, 52.5200]
        ]
      end

      it 'returns one point' do
        points = generator.build_points
        expect(points.size).to eq(1)
      end
    end
  end
end
