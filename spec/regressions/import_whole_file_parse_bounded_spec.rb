# frozen_string_literal: true

require 'rails_helper'

# Regression: a whole-file importer must refuse an input larger than
# IMPORT_MAX_PARSE_BYTES instead of reading it all into memory and OOM-killing
# the worker. A small compressed upload can expand to gigabytes on disk.
RSpec.describe 'Whole-file import parsing is size-bounded', type: :model do
  let(:host_class) do
    Class.new do
      include Imports::FileLoader

      attr_reader :file_path, :import

      def initialize(file_path)
        @file_path = file_path
      end

      def read_it = load_file_content
    end
  end

  around do |example|
    Dir.mktmpdir('parse-cap-') do |dir|
      @dir = dir
      example.run
    end
  end

  it 'raises once the file exceeds the configured limit' do
    path = File.join(@dir, 'big.json')
    File.binwrite(path, '0' * 2_048)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('IMPORT_MAX_PARSE_BYTES', anything).and_return('1024')

    expect { host_class.new(path).read_it }
      .to raise_error(Imports::FileTooLarge, /2048 bytes/)
  end

  it 'reads a file within the limit' do
    path = File.join(@dir, 'ok.json')
    File.binwrite(path, '0' * 512)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('IMPORT_MAX_PARSE_BYTES', anything).and_return('1024')

    expect(host_class.new(path).read_it).to eq('0' * 512)
  end
end
