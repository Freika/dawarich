# frozen_string_literal: true

module UrlValidatable
  extend ActiveSupport::Concern

  class BlockedUrlError < StandardError; end

  # Refuses outbound HTTP from the cloud install to internal / non-routable
  # addresses. Self-hosted bypasses this entirely (line 24) — a self-hoster
  # already controls the box; internal Immich at 192.168.x.x is normal.
  #
  # NOTE: this is a save-time check, not a request-time check. DNS rebinding
  # is still possible: an attacker can serve a public IP to the validator
  # and a private IP to the actual HTTPParty request a moment later. The
  # mitigation lives in the HTTP client (pin the resolved IP) — see
  # security-audit/REPORT.md C-3.
  #
  # (audit C-3)
  BLOCKED_RANGES = [
    IPAddr.new('0.0.0.0/8'),
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('100.64.0.0/10'),
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('169.254.0.0/16'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.0.0.0/24'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('198.18.0.0/15'),
    IPAddr.new('224.0.0.0/4'),
    IPAddr.new('240.0.0.0/4'),
    IPAddr.new('::1/128'),
    IPAddr.new('fc00::/7'),
    IPAddr.new('fe80::/10'),
    IPAddr.new('ff00::/8')
  ].freeze

  private

  def validate_integration_url!(url)
    return if DawarichSettings.self_hosted?
    return if url.blank?

    uri = URI.parse(url)
    raise BlockedUrlError, "Invalid URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)
    raise BlockedUrlError, 'URL must include a host' if uri.host.blank?
    raise BlockedUrlError, 'URL must not embed credentials (user:pass@host)' if uri.userinfo.present?

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise BlockedUrlError, 'URL resolves to a blocked address' if BLOCKED_RANGES.any? { |range| range.include?(ip) }
  rescue URI::InvalidURIError
    raise BlockedUrlError, 'Invalid URL format'
  rescue Resolv::ResolvError
    raise BlockedUrlError, "Could not resolve hostname: #{uri.host}"
  end
end
