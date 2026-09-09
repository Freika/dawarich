# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::GeocodedDays do
  include ActiveSupport::Testing::TimeHelpers

  let(:timestamp) { Time.utc(2014, 6, 15).to_i }
  let(:member) { '123:2014-06-15' }
  let(:key) { "#{described_class::VERSION_KEY_PREFIX}:#{member}" }

  before do
    config = Sidekiq.redis(&:config)
    @redis = config.new_client
    @other = config.new_client
    main = Thread.current
    allow(Sidekiq).to receive(:redis) { |&block| block.call(Thread.current == main ? @redis : @other) }
    clear_geocoded_days
  end

  after do
    clear_geocoded_days
    @redis.close
    @other.close
  end

  it 'publishes the version and queue entry together in one transaction' do
    allow(@redis).to receive(:multi).and_wrap_original do |method, &block|
      method.call do |transaction|
        block.call(transaction)
        expect(@other.call('GET', key)).to be_nil
        expect(@other.call('ZSCORE', described_class::PENDING_KEY, member)).to be_nil
      end
    end

    described_class.mark(123, timestamp)
    expect(@other.call('GET', key)).to be_present
    expect(@other.call('ZSCORE', described_class::PENDING_KEY, member)).to be_present
  end

  it 'retains and postpones a concurrent same-day mark without retrying acknowledgement' do
    described_class.mark(123, timestamp)
    travel 61.minutes do
      snapshot = described_class.due(limit: 10)
      after_version_read { write_concurrently { described_class.mark(123, timestamp) } }

      described_class.acknowledge(snapshot)

      expect(@redis).to have_received(:call).with('GET', key).once
      expect(@other.call('GET', key)).not_to eq(snapshot.fetch(member))
      expect(@other.call('ZSCORE', described_class::PENDING_KEY, member).to_i).to eq(1.hour.from_now.to_i)
      expect(described_class.due(limit: 10)).to be_empty
    end
    travel 122.minutes do
      expect(described_class.due(limit: 10).keys).to eq([member])
    end
  end

  it 'acknowledges a day while another user receives a new notification' do
    described_class.mark(123, timestamp)
    travel 61.minutes do
      snapshot = described_class.due(limit: 10)
      after_version_read { write_concurrently { described_class.mark(456, timestamp) } }

      described_class.acknowledge(snapshot)

      expect(@other.call('GET', key)).to be_nil
      expect(@other.call('ZRANGE', described_class::PENDING_KEY, 0, -1)).to eq(['456:2014-06-15'])
    end
  end

  it 'keeps a new generation when a duplicate acknowledgement wins the transaction race' do
    described_class.mark(123, timestamp)
    travel 61.minutes do
      snapshot = described_class.due(limit: 10)
      after_version_read do
        write_concurrently do
          described_class.acknowledge(snapshot)
          described_class.mark(123, timestamp)
        end
      end

      described_class.acknowledge(snapshot)

      expect(@other.call('GET', key)).to be_present
      expect(@other.call('GET', key)).not_to eq(snapshot.fetch(member))
      expect(@other.call('ZRANGE', described_class::PENDING_KEY, 0, -1)).to eq([member])
    end
  end

  it 'clears WATCH when reading the version fails before returning the connection' do
    described_class.mark(123, timestamp)
    travel 61.minutes do
      snapshot = described_class.due(limit: 10)
      allow(@redis).to receive(:call).and_call_original
      allow(@redis).to receive(:call).with('GET', key).and_raise(IOError, 'read failed')

      expect { described_class.acknowledge(snapshot) }.to raise_error(IOError, 'read failed')
      write_concurrently { described_class.mark(123, timestamp) }

      expect(@redis.multi { |transaction| transaction.call('SET', key, 'next-borrower') }).to eq(['OK'])
      expect(@other.call('GET', key)).to eq('next-borrower')
    end
  end

  def after_version_read
    allow(@redis).to receive(:call).and_wrap_original do |method, *args|
      value = method.call(*args)
      yield if args == ['GET', key]
      value
    end
  end

  def write_concurrently(&block)
    writer = Thread.new(&block)
    expect(writer.join(5)).not_to be_nil
    writer.value
  ensure
    writer&.kill if writer&.alive?
  end
end
