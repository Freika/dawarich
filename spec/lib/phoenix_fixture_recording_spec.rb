# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../app-phoenix/scripts/parity/fixture_recording'

RSpec.describe FixtureRecording do
  it 'compares fixture bytes without writing in read-back mode' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'fixture.bin')
      File.binwrite(path, "fixture\xff".b)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return(nil)
      expect(File).not_to receive(:binwrite)
      expect(FileUtils).not_to receive(:mkdir_p)

      described_class.verify(path, "fixture\xff".b)
      expect { described_class.verify(path, 'changed') }.to raise_error("#{path} differs from Rails")
    end
  end
end
