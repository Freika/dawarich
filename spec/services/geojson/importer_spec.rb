# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::Importer do
  describe '#call' do
    subject(:call_service) { service.call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
    let(:import) { create(:import, user:, name: 'geojson.json', source: :geojson) }
    let(:service) { described_class.new(import, user.id, file_path.to_s) }

    it 'creates new points from a FeatureCollection' do
      expect { call_service }.to change { Point.count }.by(10)
    end

    it 'streams without invoking the eager full-document loader' do
      expect(service).not_to receive(:load_json_data)

      expect { call_service }.to change { Point.count }.by(10)
    end

    it 'flushes points in bounded batches' do
      stub_const('Geojson::Importer::BATCH_SIZE', 3)
      allow(service).to receive(:bulk_insert_points).and_call_original

      call_service

      expect(service).to have_received(:bulk_insert_points).exactly(4).times
    end

    it 'does not insert partial data when the JSON document is truncated' do
      malformed = <<~JSON
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [13.4, 52.5] },
              "properties": { "timestamp": 1609459201 }
            }
      JSON

      Tempfile.create(['truncated', '.geojson']) do |file|
        file.write(malformed)
        file.flush
        malformed_service = described_class.new(import, user.id, file.path)
        original_count = Point.count

        expect { malformed_service.call }.to raise_error(Oj::ParseError)
        expect(Point.count).to eq(original_count)
      end
    end

    it 'rolls back and surfaces the real error when a batch insert fails mid-stream' do
      stub_const('Geojson::Importer::BATCH_SIZE', 3)
      call_count = 0
      allow(Point).to receive(:upsert_all).and_wrap_original do |original, *args, **kwargs|
        call_count += 1
        raise ActiveRecord::StatementInvalid, 'simulated batch failure' if call_count == 2

        original.call(*args, **kwargs)
      end
      original_count = Point.count

      expect { call_service }.to raise_error(ActiveRecord::StatementInvalid, /simulated batch failure/)
      expect(Point.count).to eq(original_count)
    end

    it 'rolls back all points when a feature raises after an earlier batch flushed' do
      stub_const('Geojson::Importer::BATCH_SIZE', 2)

      document = <<~JSON
        {
          "type": "FeatureCollection",
          "features": [
            { "type": "Feature", "geometry": { "type": "Point", "coordinates": [13.4, 52.5] }, "properties": { "timestamp": 1609459201 } },
            { "type": "Feature", "geometry": { "type": "Point", "coordinates": [13.5, 52.6] }, "properties": { "timestamp": 1609459262 } },
            { "type": "Feature", "geometry": { "type": "Point", "coordinates": [13.6, 52.7] }, "properties": null }
          ]
        }
      JSON

      Tempfile.create(['partial', '.geojson']) do |file|
        file.write(document)
        file.flush
        partial_service = described_class.new(import, user.id, file.path)
        original_count = Point.count

        expect { partial_service.call }.to raise_error(NoMethodError)
        expect(Point.count).to eq(original_count)
      end
    end

    it 'scrubs invalid UTF-8 without loading the full document' do
      invalid_utf8 = <<~JSON.b.sub('INVALID', "invalid \xFF")
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [13.4, 52.5] },
              "properties": { "timestamp": 1609459201, "label": "INVALID" }
            }
          ]
        }
      JSON

      Tempfile.create(['invalid-utf8', '.geojson'], binmode: true) do |file|
        file.write(invalid_utf8)
        file.flush
        invalid_utf8_service = described_class.new(import, user.id, file.path)

        expect { invalid_utf8_service.call }.to change { Point.count }.by(1)
      end
    end

    context 'when the file contains features without timestamps' do
      let(:mixed_geojson) do
        {
          type: 'FeatureCollection',
          features: [
            { type: 'Feature', geometry: { type: 'Point', coordinates: [12.3712, 51.3402] },
              properties: { timestamp: 1_709_287_200 } },
            { type: 'Feature', geometry: { type: 'Point', coordinates: [12.3812, 51.3502] },
              properties: { name: 'no time here' } },
            { type: 'Feature', geometry: { type: 'LineString',
                                           coordinates: [[12.39, 51.36], [12.40, 51.37], [12.41, 51.38]] },
              properties: {} }
          ]
        }.to_json
      end

      def with_tempfile(content)
        Tempfile.create(['timeless', '.geojson']) do |file|
          file.write(content)
          file.flush
          yield file.path
        end
      end

      it 'imports only the points that carry a timestamp' do
        with_tempfile(mixed_geojson) do |path|
          expect { described_class.new(import, user.id, path).call }.to change { Point.count }.by(1)
        end
      end

      it 'never persists a point without a timestamp' do
        with_tempfile(mixed_geojson) do |path|
          described_class.new(import, user.id, path).call
        end

        expect(Point.where(timestamp: nil).count).to eq(0)
      end

      it 'records the skipped count on the import' do
        with_tempfile(mixed_geojson) do |path|
          described_class.new(import, user.id, path).call
        end

        expect(import.reload.raw_data['skipped_timeless']).to eq(4)
      end

      it 'notifies the user how many points were skipped and why' do
        with_tempfile(mixed_geojson) do |path|
          expect { described_class.new(import, user.id, path).call }
            .to change { user.notifications.count }.by(1)
        end

        notification = user.notifications.last
        expect(notification.kind).to eq('warning')
        expect(notification.content).to include('4')
      end
    end

    context 'when every feature carries a timestamp' do
      it 'creates no skip notification' do
        expect { call_service }.not_to(change { user.notifications.count })
      end
    end
  end
end
