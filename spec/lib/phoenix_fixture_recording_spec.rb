# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
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
  it 'compares embedded JSON bodies without depending on object key order' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'closure.json')
      body = { 'modes' => { 'walking' => 0.5, 'cycling' => 0.5 }, 'entries' => [1, 2] }
      expected = { 'timeline' => { 'body' => JSON.generate(body) }, 'opaque' => '{"a":1,"b":2}' }
      File.binwrite(path, JSON.generate(expected))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return(nil)
      actual = expected.deep_dup
      actual['timeline']['body'] = JSON.generate(body.merge('modes' => body['modes'].to_a.reverse.to_h))
      verify = -> { described_class.verify(path, JSON.generate(actual), json_bodies: [%w[timeline body]]) }
      expect { verify.call }.not_to raise_error
      actual['timeline']['body'] = JSON.generate(body.merge('entries' => [2, 1]))
      expect { verify.call }.to raise_error("#{path} differs from Rails")
      actual['timeline']['body'] = JSON.generate(body.merge('modes' => { 'walking' => 9, 'cycling' => 0.5 }))
      expect { verify.call }.to raise_error("#{path} differs from Rails")
      actual['timeline']['body'] = expected['timeline']['body']
      actual['opaque'] = '{"b":2,"a":1}'
      expect { verify.call }.to raise_error("#{path} differs from Rails")
    end
  end
end
