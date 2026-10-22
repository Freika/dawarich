# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dawarich::IdleQueueCheck do
  let(:selector) do
    selector_class = Class.new do
      def acquire(queues, namespace)
        [queues, namespace]
      end
    end
    selector_class.prepend(described_class)
    selector_class.new
  end
  let(:connection) { double('Redis connection') }

  before { allow(Sidekiq).to receive(:redis).and_yield(connection) }

  it 'skips lock acquisition when all queue lists are absent' do
    allow(connection).to receive(:exists).with('queue:default', 'queue:points').and_return(0)

    expect(selector.acquire(%w[default points], '')).to eq([])
  end

  it 'retains the entire ordered queue list when any queue has work' do
    allow(connection).to receive(:exists).with('queue:default', 'queue:points').and_return(1)

    expect(selector.acquire(%w[default points], '')).to eq([%w[default points], ''])
  end

  it 'checks the supplied namespace without changing selector arguments' do
    allow(connection).to receive(:exists).with('tenant:queue:points').and_return(1)

    expect(selector.acquire(['points'], 'tenant:')).to eq([['points'], 'tenant:'])
  end

  it 'does not query Redis when no queues are configured' do
    expect(connection).not_to receive(:exists)

    expect(selector.acquire([], '')).to eq([])
  end

  it 'checks again on the next poll so newly enqueued work is not stranded' do
    allow(connection).to receive(:exists).with('queue:default').and_return(0, 1)

    expect(selector.acquire(['default'], '')).to eq([])
    expect(selector.acquire(['default'], '')).to eq([['default'], ''])
  end

  it 'lets connection errors reach the existing fetch retry handler' do
    allow(connection).to receive(:exists).and_raise(RedisClient::ConnectionError)

    expect { selector.acquire(['default'], '') }.to raise_error(RedisClient::ConnectionError)
  end
end

RSpec.describe 'Idle queue checks with Redis limit enforcement' do
  let(:namespace) { "idle-fetch-spec:#{SecureRandom.hex(8)}:" }
  let(:selector) do
    selector_class = Class.new do
      include Sidekiq::LimitFetch::Global::Selector
      prepend Dawarich::IdleQueueCheck
    end
    selector_class.new
  end

  after do
    Sidekiq.redis do |connection|
      keys = connection.keys("#{namespace}*")
      connection.del(*keys) if keys.any?
    end
  end

  it 'does not create probe locks for empty queues' do
    3.times { expect(selector.acquire(%w[default points], namespace)).to eq([]) }

    expect(Sidekiq.redis { |connection| connection.keys("#{namespace}limit_fetch:probed:*") }).to eq([])
  end

  it 'acquires newly populated queues and still enforces the shared limit' do
    expect(selector.acquire(['points'], namespace)).to eq([])
    Sidekiq.redis do |connection|
      connection.lpush("#{namespace}queue:points", 'pending job')
      connection.set("#{namespace}limit_fetch:limit:points", 1)
    end

    expect(selector.acquire(['points'], namespace)).to eq(['points'])
    expect(selector.acquire(['points'], namespace)).to eq([])

    selector.release(['points'], namespace)
    expect(selector.acquire(['points'], namespace)).to eq(['points'])
  end

  it 'keeps populated paused queues unavailable' do
    Sidekiq.redis do |connection|
      connection.lpush("#{namespace}queue:points", 'pending job')
      connection.set("#{namespace}limit_fetch:pause:points", '1')
    end

    expect(selector.acquire(['points'], namespace)).to eq([])
  end
end
