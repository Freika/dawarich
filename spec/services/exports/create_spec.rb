# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe Exports::Create do
  describe '#call' do
    subject(:create_export) { described_class.new(export:).call }

    let(:file_format)     { :json }
    let(:user)            { create(:user) }
    let(:start_at)        { DateTime.new(2021, 1, 1).to_s }
    let(:end_at)          { DateTime.new(2021, 1, 2).to_s }
    let(:export_name)     { "#{start_at.to_date}_#{end_at.to_date}.#{file_format}" }
    let(:export) do
      create(:export, user:, name: export_name, status: :created, file_format: file_format, start_at:, end_at:)
    end
    let(:reverse_geocoded_at) { Time.zone.local(2021, 1, 1) }
    let!(:points) do
      10.times.map do |i|
        create(:point, :with_known_location,
               user: user,
               timestamp: start_at.to_datetime.to_i + i,
               reverse_geocoded_at: reverse_geocoded_at)
      end
    end

    before do
      allow_any_instance_of(Point).to receive(:reverse_geocoded_at).and_return(reverse_geocoded_at)
    end

    def read_inner_bytes(blob)
      Tempfile.create(['download', '.zip'], binmode: true) do |tf|
        tf.write(blob.download)
        tf.rewind
        ::Zip::File.open(tf.path) do |zf|
          entry = zf.entries.first
          return [entry.name, entry.get_input_stream.read]
        end
      end
    end

    it 'attaches the export as a single-entry zip with application/zip content type' do
      create_export
      blob = export.reload.file.blob

      expect(blob.content_type).to eq('application/zip')
      expect(blob.filename.to_s).to eq("#{export_name}.zip")
    end

    it 'writes valid GeoJSON as the inner entry' do
      create_export
      blob = export.reload.file.blob

      entry_name, inner = read_inner_bytes(blob)
      expect(entry_name).to eq(export_name)

      json = JSON.parse(inner)
      expect(json['type']).to eq('FeatureCollection')
      expect(json['features'].size).to eq(10)
    end

    it 'updates the export status to completed' do
      create_export

      expect(export.reload.completed?).to be_truthy
    end

    it 'creates a notification' do
      expect { create_export }.to change { Notification.count }.by(1)
    end

    context 'when file format is gpx' do
      let(:file_format) { :gpx }

      it 'writes valid GPX as the inner entry' do
        create_export
        blob = export.reload.file.blob

        _name, inner = read_inner_bytes(blob)
        expect(inner).to include('<gpx')
        expect(inner).to include('<trkpt')
      end

      it 'updates the export status to completed' do
        create_export

        expect(export.reload.completed?).to be_truthy
      end
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Exports::PointGeojsonSerializer)
          .to receive(:call).and_raise(StandardError, 'test error')
      end

      it 'updates the export status to failed' do
        create_export

        expect(export.reload.failed?).to be_truthy
      end

      it 'stores the error message' do
        create_export

        expect(export.reload.error_message).to eq('test error')
      end

      it 'creates a notification' do
        expect { create_export }.to change { Notification.count }.by(1)
      end
    end
  end
end
