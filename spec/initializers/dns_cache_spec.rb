# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'DNS cache initializer' do
  describe 'non-String hosts' do
    it 'lets the original resolver raise for nil names' do
      expect { Resolv.getaddress(nil) }.to raise_error(ArgumentError, /cannot interpret as DNS name/)
    end

    it 'lets the original resolver raise for names that are not string-like' do
      expect { Resolv.getaddress(42) }.to raise_error(TypeError, /no implicit conversion/)
    end
  end

  describe 'IP address literals' do
    it 'returns them without a DNS lookup' do
      expect(Resolv.getaddress('127.0.0.1')).to eq('127.0.0.1')
    end
  end

  describe 'hostnames' do
    it 'resolves once and serves later calls from the cache' do
      allow(Resolv).to receive(:getaddress_without_cache).and_return('203.0.113.10')

      expect(Resolv.getaddress('cache-me.invalid')).to eq('203.0.113.10')
      expect(Resolv.getaddress('cache-me.invalid')).to eq('203.0.113.10')

      expect(Resolv).to have_received(:getaddress_without_cache).once
    end
  end
end
