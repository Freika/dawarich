# frozen_string_literal: true

require 'rails_helper'

# Regression: a whole-file importer must refuse an input larger than the limit
# in Admin → Settings → Imports instead of reading it all into memory and
# OOM-killing the worker. A small compressed upload can expand to gigabytes.
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
    InstanceSettings::Resolver.reset!
    Dir.mktmpdir('parse-cap-') do |dir|
      @dir = dir
      example.run
    end
  ensure
    InstanceSettings::Resolver.reset!
  end

  def write_file(name, bytes)
    File.join(@dir, name).tap { |path| File.binwrite(path, '0' * bytes) }
  end

  it 'raises once the file exceeds the limit set in the instance settings' do
    InstanceSettings::Resolver.set(:import_max_file_size_mb, 1)
    path = write_file('big.json', 1.megabyte + 1)

    expect { host_class.new(path).read_it }
      .to raise_error(Imports::FileTooLarge, /#{1.megabyte + 1} bytes.*Settings → Instance → Imports/)
  end

  it 'reads a file within the limit' do
    InstanceSettings::Resolver.set(:import_max_file_size_mb, 1)
    path = write_file('ok.json', 512)

    expect(host_class.new(path).read_it).to eq('0' * 512)
  end

  it 'ignores the IMPORT_MAX_PARSE_BYTES variable an earlier build read' do
    stub_const('ENV', ENV.to_h.merge('IMPORT_MAX_PARSE_BYTES' => '10'))
    path = write_file('ok.json', 512)

    expect(host_class.new(path).read_it).to eq('0' * 512)
  end

  it 'refuses a KML file above the KML limit, which is lower than the general one' do
    InstanceSettings::Resolver.set(:kml_max_file_size_mb, 1)
    path = write_file('big.kml', 1.megabyte + 1)
    import = create(:import, name: 'big.kml', source: 'kml')

    expect { Kml::Importer.new(import, import.user_id, path).call }
      .to raise_error(Imports::FileTooLarge, /Settings → Instance → Imports/)
  end
end
