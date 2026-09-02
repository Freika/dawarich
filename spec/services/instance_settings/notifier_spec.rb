# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceSettings::Notifier do
  describe '.publish' do
    it 'publishes the key name so subscribers re-read, never the value' do
      redis = instance_double(Redis)
      allow(described_class).to receive(:redis).and_return(redis)

      expect(redis).to receive(:publish) do |channel, payload|
        expect(channel).to eq(described_class::CHANNEL)
        expect(payload).to include('geoapify_api_key')
        expect(payload).not_to include('super-secret')
      end

      described_class.publish(:geoapify_api_key)
    end

    it 'never lets a publishing failure escape into the caller saving a setting' do
      redis = instance_double(Redis)
      allow(described_class).to receive(:redis).and_return(redis)
      allow(redis).to receive(:publish).and_raise(Redis::BaseConnectionError, 'down')

      expect { described_class.publish(:store_geodata) }.not_to raise_error
    end
  end

  describe '.handle_message' do
    it 'drops the resolver snapshot so the next read reloads' do
      expect(InstanceSettings::Resolver).to receive(:reset!)

      described_class.handle_message({ 'key' => 'store_geodata' }.to_json)
    end

    it 'ignores a malformed payload rather than killing the subscriber thread' do
      expect { described_class.handle_message('not json') }.not_to raise_error
    end
  end

  describe 'the subscriber loop' do
    before { allow(described_class).to receive(:sleep) }

    it 'subscribes to the channel and clears the snapshot on a message' do
      handler = nil
      on = double('on')
      allow(on).to receive(:message) { |&blk| handler = blk }
      subscriber = instance_double(Redis)
      allow(subscriber).to receive(:subscribe) do |channel, &blk|
        expect(channel).to eq(described_class::CHANNEL)
        blk.call(on)
      end
      allow(Redis).to receive(:new).and_return(subscriber)

      expect(InstanceSettings::Resolver).to receive(:reset!)

      described_class.send(:listen_once)
      handler.call(described_class::CHANNEL, { 'key' => 'store_geodata' }.to_json)
    end

    it 'swallows a connection error so the loop can retry instead of dying' do
      allow(Redis).to receive(:new).and_raise(Redis::BaseConnectionError, 'down')

      expect { described_class.send(:listen_once) }.not_to raise_error
    end

    it 'backs off after a failed attempt' do
      allow(Redis).to receive(:new).and_raise(Redis::BaseConnectionError, 'down')

      described_class.send(:listen_once)

      expect(described_class).to have_received(:sleep).with(described_class::RECONNECT_BACKOFF)
    end
  end

  describe '.start' do
    # A thread leaking into the suite is a flake source, and the test process
    # has no second process to stay in sync with.
    it 'does not spawn a subscriber under the test environment' do
      expect(Thread).not_to receive(:new)

      described_class.start
    end
  end
end
