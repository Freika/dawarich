# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exports::PointGeojsonSerializer do
  describe '#call' do
    let(:user) { create(:user) }
    let(:start_time) { DateTime.new(2021, 1, 1).to_i }
    let!(:points) do
      5.times.map do |i|
        create(:point, :with_known_location, user: user, timestamp: start_time + i)
      end
    end
    let(:scope) { user.points.where(timestamp: start_time..(start_time + 10)) }

    subject(:serializer) { described_class.new(scope) }

    it 'returns a Tempfile' do
      result = serializer.call
      expect(result).to be_a(Tempfile)
      result.close!
    end

    it 'produces valid GeoJSON FeatureCollection' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      expect(json['type']).to eq('FeatureCollection')
      expect(json['features'].size).to eq(5)
    end

    it 'serializes each point as a Feature with correct coordinates' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      feature = json['features'].first
      expect(feature['type']).to eq('Feature')
      expect(feature['geometry']['type']).to eq('Point')
      expect(feature['geometry']['coordinates']).to be_an(Array)
      expect(feature['geometry']['coordinates'].size).to eq(2)
    end

    it 'includes point properties via PointSerializer' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      properties = json['features'].first['properties']
      expect(properties).to have_key('latitude')
      expect(properties).to have_key('longitude')
      expect(properties).to have_key('timestamp')
    end

    it 'produces empty features array when no points exist' do
      scope = user.points.where(timestamp: 0..1)
      result = described_class.new(scope).call
      json = JSON.parse(result.read)
      result.close!

      expect(json['features']).to eq([])
    end

    # The point serializer reads the device combo through each point's
    # source; without the per-batch preload every stamped point costs its
    # own dimension query across a whole export.
    it 'loads the dimension in one query per batch, not one per point' do
      3.times do |i|
        point = create(:point, user: user, timestamp: 1_700_000_000 + i)
        source = PointSource.create!(digest: format('%032x', i), tracker_id: "device-#{i}")
        point.update_columns(source_id: source.id)
      end

      dimension_queries = []
      callback = lambda do |_name, _started, _finished, _id, payload|
        dimension_queries << payload[:sql] if payload[:sql].to_s.include?('point_sources')
      end

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.new(user.points.order(:timestamp)).call.close!
      end

      expect(dimension_queries.size).to eq(1)
    end
  end
end
