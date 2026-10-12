# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Integration URLs resolving to an IPv4-mapped IPv6 address' do
  let(:test_class) do
    Class.new do
      include UrlValidatable
      public :validate_integration_url!
    end
  end

  subject(:validator) { test_class.new }

  # IPAddr#include? is false across address families, so an IPv4 address
  # wearing an IPv6 coat clears every IPv4 range in the blocklist while the
  # OS still routes it to the bare IPv4 host.
  {
    'IPv4-mapped cloud metadata'     => '::ffff:169.254.169.254',
    'IPv4-compatible cloud metadata' => '::169.254.169.254'
  }.each do |label, address|
    it "rejects #{label} on self-hosted" do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      stub_host_addresses('metadata.example.test', address)

      expect { validator.validate_integration_url!('http://metadata.example.test') }
        .to raise_error(UrlValidatable::BlockedUrlError, /blocked/i)
    end
  end

  {
    'IPv4-mapped loopback' => '::ffff:127.0.0.1',
    'IPv4-mapped RFC1918'  => '::ffff:192.168.1.10',
    'IPv4-mapped CGNAT'    => '::ffff:100.64.0.1'
  }.each do |label, address|
    it "rejects #{label} on cloud" do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      stub_host_addresses('internal.example.test', address)

      expect { validator.validate_integration_url!('http://internal.example.test') }
        .to raise_error(UrlValidatable::BlockedUrlError, /blocked/i)
    end
  end

  it 'still allows a routable IPv6 address' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_host_addresses('immich.example.test', '2606:2800:220:1::1')

    expect { validator.validate_integration_url!('http://immich.example.test') }.not_to raise_error
  end
end
