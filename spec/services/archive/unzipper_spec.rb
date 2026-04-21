# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe Archive::Unzipper do
  def make_zip(entries)
    path = Rails.root.join('tmp', "unzipper_#{SecureRandom.hex(4)}.zip").to_s
    ::Zip::File.open(path, create: true) do |zf|
      entries.each do |name, content|
        zf.get_output_stream(name) { |f| f.write(content) }
      end
    end
    path
  end

  def write_raw(ext, content)
    tempfile = Tempfile.new(['raw', ext], binmode: true)
    tempfile.write(content)
    tempfile.close
    tempfile.path
  end

  describe '.inspect_archive' do
    it 'classifies a single-entry zip with a supported inner extension as :single_entry' do
      path = make_zip('ride.gpx' => '<gpx/>')
      result = described_class.inspect_archive(path)
      expect(result.kind).to eq(:single_entry)
      expect(result.entry_name).to eq('ride.gpx')
    ensure
      File.delete(path) if path && File.exist?(path)
    end

    it 'classifies a multi-entry zip as :multi_entry' do
      path = make_zip('a.gpx' => '<gpx/>', 'b.gpx' => '<gpx/>')
      result = described_class.inspect_archive(path)
      expect(result.kind).to eq(:multi_entry)
    ensure
      File.delete(path) if path && File.exist?(path)
    end

    it 'classifies a single-entry zip with an unsupported inner extension as :multi_entry' do
      path = make_zip('readme.txt' => 'hi')
      result = described_class.inspect_archive(path)
      expect(result.kind).to eq(:multi_entry)
    ensure
      File.delete(path) if path && File.exist?(path)
    end

    it 'classifies a non-zip file as :not_a_zip' do
      path = write_raw('.gpx', '<gpx/>')
      result = described_class.inspect_archive(path)
      expect(result.kind).to eq(:not_a_zip)
    ensure
      File.delete(path) if path && File.exist?(path)
    end

    it 'classifies a corrupted file starting with PK but invalid content as :not_a_zip' do
      path = write_raw('.bin', "PK\x03\x04garbage")
      result = described_class.inspect_archive(path)
      expect(result.kind).to eq(:not_a_zip)
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end

  describe '.extract_single' do
    it 'writes the inner entry to a new tempfile path and returns it' do
      zip_path = make_zip('ride.gpx' => '<gpx>hello</gpx>')
      inner_path = described_class.extract_single(zip_path)

      expect(File.read(inner_path)).to eq('<gpx>hello</gpx>')
      expect(File.extname(inner_path)).to eq('.gpx')
    ensure
      File.delete(zip_path) if zip_path && File.exist?(zip_path)
      File.delete(inner_path) if inner_path && File.exist?(inner_path)
    end

    it 'raises when the inflated size exceeds the configured limit' do
      stub_const("#{described_class}::MAX_EXTRACTED_SIZE", 10)
      zip_path = make_zip('ride.gpx' => 'x' * 100)

      expect { described_class.extract_single(zip_path) }
        .to raise_error(Archive::Unzipper::ArchiveTooLarge)
    ensure
      File.delete(zip_path) if zip_path && File.exist?(zip_path)
    end
  end
end
