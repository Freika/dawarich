# frozen_string_literal: true

module HostAddressStubs
  def stub_host_addresses(host, *addresses)
    stub_address_lookups
    allow(Addrinfo).to receive(:getaddrinfo)
      .with(host, nil, nil, :STREAM)
      .and_return(addresses.map { |address| Addrinfo.tcp(address, 0) })
  end

  def stub_unresolvable_host(host)
    stub_address_lookups
    allow(Addrinfo).to receive(:getaddrinfo).with(host, nil, nil, :STREAM).and_raise(SocketError)
  end

  private

  def stub_address_lookups
    @stub_address_lookups ||= allow(Addrinfo).to receive(:getaddrinfo).and_call_original
  end
end

RSpec.configure { |config| config.include HostAddressStubs }
