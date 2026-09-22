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
    before do
      %w[cache-me.invalid dual-stack.invalid ipv6-only.invalid missing.invalid].each do |host|
        Rails.cache.delete("dawarich/dns:#{host}")
      end
    end

    it 'resolves once and serves later calls from the cache' do
      allow(Resolv).to receive(:getaddresses).with('cache-me.invalid').and_return(['203.0.113.10'])

      expect(Resolv.getaddress('cache-me.invalid')).to eq('203.0.113.10')
      expect(Resolv.getaddress('cache-me.invalid')).to eq('203.0.113.10')

      expect(Resolv).to have_received(:getaddresses).once
    end

    it 'caches the IPv4 address when a host has both address families' do
      allow(Resolv).to receive(:getaddresses).with('dual-stack.invalid').and_return(%w[2001:db8::1 203.0.113.10])

      expect(Resolv.getaddress('dual-stack.invalid')).to eq('203.0.113.10')
    end

    it 'keeps IPv6-only hosts resolvable' do
      allow(Resolv).to receive(:getaddresses).with('ipv6-only.invalid').and_return(['2001:db8::1'])

      expect(Resolv.getaddress('ipv6-only.invalid')).to eq('2001:db8::1')
    end

    it 'still raises for unresolvable hosts' do
      allow(Resolv::DefaultResolver).to receive(:each_address).with('missing.invalid')

      expect { Resolv.getaddress('missing.invalid') }.to raise_error(Resolv::ResolvError)
    end
  end
end
