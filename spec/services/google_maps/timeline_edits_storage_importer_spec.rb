# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::TimelineEditsStorageImporter do
  let(:user) { create(:user) }
  let(:import) { create(:import, source: 'google_timeline_edits', user: user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/google/timeline_edits.json') }

  before do
    import.file.attach(
      io: File.open(file_path),
      filename: 'timeline_edits.json',
      content_type: 'application/json'
    )
  end

  subject(:service) { described_class.new(import, user.id, file_path.to_s) }

  describe '#call' do
    it 'imports the position entries from the fixture (skipping non-position signals)' do
      expect { service.call }.to change(Point, :count).by(2)
    end

    context 'when the file has more entries than the batch size' do
      let(:large_payload) do
        edits = Array.new(1001) do |i|
          {
            'deviceId' => '799010011',
            'rawSignal' => {
              'signal' => {
                'position' => {
                  'point' => { 'latE7' => 679_651_561 + i, 'lngE7' => 236_850_278 + i },
                  'accuracyMm' => 9000,
                  'altitudeMeters' => 280.0,
                  'source' => 'GPS',
                  'timestamp' => "2024-03-13T#{format('%02d', 14 + (i / 3600))}:#{format('%02d', (i / 60) % 60)}:#{format('%02d', i % 60)}.000Z"
                }
              }
            }
          }
        end
        { 'timelineEdits' => edits }.to_json
      end

      before do
        import.file.purge
        import.file.attach(
          io: StringIO.new(large_payload),
          filename: 'timeline_edits.json',
          content_type: 'application/json'
        )
      end

      subject(:service) { described_class.new(import, user.id) }

      it 'processes records in 1000-row batches and a final partial batch' do
        mock_importer = instance_double(GoogleMaps::TimelineEditsImporter)
        allow(GoogleMaps::TimelineEditsImporter).to receive(:new).and_return(mock_importer)
        allow(mock_importer).to receive(:call)

        service.call

        expect(GoogleMaps::TimelineEditsImporter).to have_received(:new).with(import, 0).ordered
        expect(GoogleMaps::TimelineEditsImporter).to have_received(:new).with(import, 1000).ordered
        expect(mock_importer).to have_received(:call).exactly(2).times
      end
    end

    context 'when timelineEdits is empty' do
      let(:empty_payload) { { 'timelineEdits' => [] }.to_json }

      before do
        import.file.purge
        import.file.attach(
          io: StringIO.new(empty_payload),
          filename: 'timeline_edits.json',
          content_type: 'application/json'
        )
      end

      subject(:service) { described_class.new(import, user.id) }

      it 'does not create any Points and does not raise' do
        expect { service.call }.not_to change(Point, :count)
      end
    end

    context 'when the JSON has no timelineEdits key' do
      let(:bogus_payload) { { 'somethingElse' => [] }.to_json }

      before do
        import.file.purge
        import.file.attach(
          io: StringIO.new(bogus_payload),
          filename: 'timeline_edits.json',
          content_type: 'application/json'
        )
      end

      subject(:service) { described_class.new(import, user.id) }

      it 'returns silently' do
        expect { service.call }.not_to raise_error
        expect(Point.count).to eq(0)
      end
    end
  end
end
