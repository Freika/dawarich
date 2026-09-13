# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import temporary file lifetime' do
  let(:content) { '<gpx><trk><trkseg><trkpt lat="1" lon="2"/></trkseg></trk></gpx>' }
  let(:byte_size) { content.bytesize }
  let(:checksum) { Base64.strict_encode64(Digest::MD5.digest(content)) }
  let(:download_errors) { [] }
  let(:blob) { Struct.new(:byte_size, :checksum, :download).new(byte_size, checksum, content) }
  let(:attachment) do
    Struct.new(:blob, :content, :errors) do
      def filename = 'synthetic.gpx'

      def download
        error = errors.shift
        raise error if error

        yield content
      end
    end.new(blob, content, download_errors)
  end

  around do |example|
    Dir.mktmpdir('import-download-') do |directory|
      @download_directory = directory
      example.run
    end
  end

  before do
    allow(Dir).to receive(:tmpdir).and_return(@download_directory)
  end

  def download
    Imports::SecureFileDownloader.new(attachment).download_to_temp_file
  end

  it 'keeps the downloaded file readable after the downloader stack is released and GC runs' do
    path = Thread.new { download }.value
    3.times { GC.start(full_mark: true, immediate_sweep: true) }

    expect(File.binread(path)).to eq(content)
  end

  shared_examples 'a rejected download without leftover files' do |error|
    it 'preserves the error and removes the temporary file' do
      expect { download }.to raise_error(error)
      expect(Dir.children(@download_directory)).to be_empty
    end
  end

  context 'when both download methods return empty content' do
    let(:content) { '' }

    include_examples 'a rejected download without leftover files', /no content was received/
  end

  context 'when the size does not match' do
    let(:byte_size) { content.bytesize + 1 }

    include_examples 'a rejected download without leftover files', /Incomplete download/
  end

  context 'when the checksum does not match' do
    let(:checksum) { 'invalid' }

    include_examples 'a rejected download without leftover files', /Checksum mismatch/
  end

  context 'when storage raises an error' do
    let(:download_errors) { [IOError.new('storage failure')] }

    include_examples 'a rejected download without leftover files', IOError
  end

  context 'when every attempt times out' do
    let(:download_errors) { Array.new(Imports::SecureFileDownloader::MAX_RETRIES + 1) { Timeout::Error.new } }

    include_examples 'a rejected download without leftover files', Timeout::Error
  end

  context 'when a retry succeeds' do
    let(:download_errors) { [Timeout::Error.new, Timeout::Error.new] }

    it 'retains only the successful download' do
      path = download

      expect(File.binread(path)).to eq(content)
      expect(Dir.children(@download_directory)).to eq([File.basename(path)])
    end
  end
end
