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
    # Hosts this example did not stub keep the suite-wide default from
    # spec/support/integration_host_addresses.rb rather than real DNS.
    @stub_address_lookups ||= allow(Addrinfo).to receive(:getaddrinfo).and_wrap_original do |original, host, *rest|
      IntegrationHostAddresses.resolve(original, host, *rest)
    end
  end
end

RSpec.configure { |config| config.include HostAddressStubs }
