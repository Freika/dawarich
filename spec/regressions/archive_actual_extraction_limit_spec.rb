# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'User archive actual extraction size' do
  let(:user) { create(:user) }

  around do |example|
    Dir.mktmpdir('archive-size-limit') do |directory|
      @directory = Pathname.new(directory)
      example.run
    end
  end

  before { stub_const('Users::ImportData::MAX_ENTRY_SIZE', 1024) }

  def archive(size, declared_size: size)
    path = @directory.join('archive.zip')
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('payload.txt')
      zip.write('x' * size)
    end
    bytes = File.binread(path)
    central_directory = bytes.index("PK\x01\x02".b)
    bytes[central_directory + 24, 4] = [declared_size].pack('V')
    File.binwrite(path, bytes)
    path
  end

  def extractor(path)
    service = Users::ImportData.new(user, path)
    service.instance_variable_set(:@import_directory, @directory.join('extracted'))
    service
  end

  it 'rejects an understated ZIP size before writing beyond the actual-byte ceiling' do
    path = archive(4096, declared_size: 1)
    Zip::File.open(path) { |zip| expect(zip.entries.sole.size).to eq(1) }

    expect { extractor(path).send(:extract_archive) }.to raise_error(/exceeds maximum allowed size/)
    expect(File.size(@directory.join('extracted/payload.txt'))).to be <= 1024
  end

  [1023, 1024].each do |size|
    it "extracts a legitimate #{size}-byte entry intact" do
      extractor(archive(size)).send(:extract_archive)

      expect(File.binread(@directory.join('extracted/payload.txt'))).to eq('x' * size)
    end
  end

  it 'cleans up the restore directory after detecting a forged size' do
    service = Users::ImportData.new(user, archive(4096, declared_size: 1))

    expect { service.import }.to raise_error(/exceeds maximum allowed size/)
    expect(service.instance_variable_get(:@import_directory)).not_to exist
    expect(user.notifications.where(kind: :error)).to exist
  end
end
