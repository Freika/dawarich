# frozen_string_literal: true

# Integrations::Transport validates the address of every request, so any spec
# that reaches an integration client resolves its hostname. Without this, hosts
# from factories (immich.app, *.example.com, *.local) would hit public DNS,
# NXDOMAIN or an mDNS stall. Unstubbed hostnames resolve to a TEST-NET address;
# IP literals and localhost go to the real resolver. stub_host_addresses and
# stub_unresolvable_host override this per example.
module IntegrationHostAddresses
  DEFAULT_ADDRESS = '203.0.113.10'
  VALIDATOR_ARGUMENTS = [nil, nil, :STREAM].freeze

  def self.resolve(original, host, *rest)
    return original.call(host, *rest) unless rest == VALIDATOR_ARGUMENTS
    return original.call(host, *rest) if host == 'localhost' || ip_literal?(host)

    [Addrinfo.tcp(DEFAULT_ADDRESS, 0)]
  end

  def self.ip_literal?(host)
    IPAddr.new(host.to_s)
    true
  rescue IPAddr::Error
    false
  end
end

RSpec.configure do |config|
  config.before do
    allow(Addrinfo).to receive(:getaddrinfo).and_wrap_original do |original, host, *rest|
      IntegrationHostAddresses.resolve(original, host, *rest)
    end
  end
end
