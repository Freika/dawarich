# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::Detector do
  describe '#call' do
    context 'with GPSLogger CSV (comma-delimited)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/gpslogger.csv').to_s }
      let(:result) { described_class.new(file_path).call }

      it 'detects comma delimiter' do
        expect(result[:delimiter]).to eq(',')
      end

      it 'maps latitude column' do
        expect(result[:columns][:latitude]).to be_a(Integer)
      end

      it 'maps longitude column' do
        expect(result[:columns][:longitude]).to be_a(Integer)
      end

      it 'maps timestamp column' do
        expect(result[:columns][:timestamp]).to be_a(Integer)
      end

      it 'detects decimal degrees coordinate format' do
        expect(result[:coordinate_format]).to eq(:decimal_degrees)
      end

      it 'detects ISO 8601 timestamp format' do
        expect(result[:timestamp_format]).to eq(:iso8601)
      end

      it 'does not enable comma decimal replacement' do
        expect(result[:comma_decimals]).to be false
      end
    end

    context 'with semicolon-delimited EU CSV' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/semicolon_eu.csv').to_s }
      let(:result) { described_class.new(file_path).call }

      it 'detects semicolon delimiter' do
        expect(result[:delimiter]).to eq(';')
      end

      it 'enables comma decimal replacement' do
        expect(result[:comma_decimals]).to be true
      end

      it 'maps all required columns' do
        expect(result[:columns][:latitude]).to be_a(Integer)
        expect(result[:columns][:longitude]).to be_a(Integer)
        expect(result[:columns][:timestamp]).to be_a(Integer)
      end
    end

    context 'with Unix timestamps' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/unix_timestamps.csv').to_s }
      let(:result) { described_class.new(file_path).call }

      it 'detects Unix seconds timestamp format' do
        expect(result[:timestamp_format]).to eq(:unix_seconds)
      end
    end

    context 'with N/S E/W coordinate suffixes' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/nsew_suffixes.csv').to_s }
      let(:result) { described_class.new(file_path).call }

      it 'detects directional coordinate format' do
        expect(result[:coordinate_format]).to eq(:directional)
      end
    end

    context 'with E7 integer coordinates' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/csv/e7_integers.csv').to_s }
      let(:result) { described_class.new(file_path).call }

      it 'detects E7 coordinate format' do
        expect(result[:coordinate_format]).to eq(:e7)
      end
    end

    context 'with missing required columns' do
      it 'raises DetectionError with recognized column names' do
        file = Tempfile.new(['bad', '.csv'])
        file.write("foo,bar,baz\n1,2,3\n")
        file.rewind

        expect { described_class.new(file.path).call }.to raise_error(
          Csv::Detector::DetectionError, /latitude.*longitude.*timestamp/i
        )
      ensure
        file&.close
        file&.unlink
      end
    end
  end
end
