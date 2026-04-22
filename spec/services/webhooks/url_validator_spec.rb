# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::UrlValidator do
  describe '.call' do
    context 'on cloud (not self-hosted)' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'allows public https URLs' do
        expect(described_class.call('https://example.com/hook')).to eq(:ok)
      end

      it 'rejects non-https URLs' do
        expect(described_class.call('http://example.com/hook')).to eq(:invalid_scheme)
      end

      it 'rejects localhost' do
        expect(described_class.call('https://localhost/hook')).to eq(:private_address)
      end

      it 'rejects 127.0.0.1' do
        expect(described_class.call('https://127.0.0.1/hook')).to eq(:private_address)
      end

      it 'rejects RFC1918 10.0.0.0/8' do
        expect(described_class.call('https://10.1.2.3/hook')).to eq(:private_address)
      end

      it 'rejects 192.168.0.0/16' do
        expect(described_class.call('https://192.168.1.1/hook')).to eq(:private_address)
      end

      it 'rejects 172.16.0.0/12' do
        expect(described_class.call('https://172.16.0.1/hook')).to eq(:private_address)
      end
    end

    context 'on self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'allows http and private IPs' do
        expect(described_class.call('http://192.168.1.1/hook')).to eq(:ok)
      end
    end

    context 'malformed URLs' do
      it 'rejects non-URL strings' do
        expect(described_class.call('not a url')).to eq(:invalid_format)
      end
    end
  end
end
