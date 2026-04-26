# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe Archive::Zipper do
  describe '.wrap' do
    let(:payload_bytes) { "hello world\n" * 100 }
    let(:payload_tempfile) do
      tempfile = Tempfile.new(['payload', '.gpx'], binmode: true)
      tempfile.write(payload_bytes)
      tempfile.rewind
      tempfile
    end

    after do
      payload_tempfile.close!
    end

    it 'returns a tempfile containing a single-entry zip with the expected entry name and bytes' do
      zipped = described_class.wrap(payload_tempfile, entry_name: 'ride.gpx')

      begin
        entries = ::Zip::File.open(zipped.path) { |zf| zf.entries.map(&:name) }
        expect(entries).to eq(['ride.gpx'])

        inner = ::Zip::File.open(zipped.path) do |zf|
          zf.glob('ride.gpx').first.get_input_stream.read
        end
        expect(inner).to eq(payload_bytes)
      ensure
        zipped.close!
      end
    end

    it 'produces a smaller file than the input for compressible text' do
      zipped = described_class.wrap(payload_tempfile, entry_name: 'ride.gpx')

      begin
        expect(File.size(zipped.path)).to be < payload_bytes.bytesize
      ensure
        zipped.close!
      end
    end

    it 'closes and unlinks the output tempfile when zip creation fails' do
      allow(::Zip::OutputStream).to receive(:open).and_raise(Zip::Error, 'disk full')

      before_count = Dir["#{Dir.tmpdir}/archive*.zip"].size

      expect do
        described_class.wrap(payload_tempfile, entry_name: 'ride.gpx')
      end.to raise_error(Zip::Error, 'disk full')

      GC.start
      GC.start

      after_count = Dir["#{Dir.tmpdir}/archive*.zip"].size
      expect(after_count).to eq(before_count)
    end
  end
end
