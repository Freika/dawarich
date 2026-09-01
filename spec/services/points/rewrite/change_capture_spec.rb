# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::Rewrite::ChangeCapture do
  subject(:capture) { described_class.new(connection) }

  let(:connection) { ActiveRecord::Base.connection }

  after { capture.drop }

  it 'installs the trigger once and skips the DDL when it is already there' do
    capture.install
    expect(capture).to be_installed

    allow(connection).to receive(:execute).and_call_original
    capture.install

    expect(connection).not_to have_received(:execute).with(/CREATE (OR REPLACE )?TRIGGER/)
  end

  it 'retries the trigger install when the lock times out' do
    attempts = 0
    allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
      if args.first.include?('TRIGGER') && (attempts += 1) == 1
        raise ActiveRecord::LockWaitTimeout, 'canceling statement due to lock timeout'
      end

      original.call(*args, **kwargs)
    end
    allow(capture).to receive(:sleep)

    capture.install

    expect(capture).to be_installed
    expect(attempts).to eq(2)
  end

  it 'bounds the trigger install with a lock timeout' do
    statements = []
    allow(connection).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
      statements << args.first
      original.call(*args, **kwargs)
    end

    capture.install

    expect(statements).to include(a_string_matching(/SET LOCAL lock_timeout/))
  end
end
