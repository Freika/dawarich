# frozen_string_literal: true

# Validates user-supplied integration URLs (immich_url, photoprism_url) at
# save time. Catches obvious SSRF attempts and configuration mistakes before
# the URL ever reaches HTTPParty.
#
# Two tiers of strictness, chosen at request time from DawarichSettings:
#
# - **Cloud (dawarich.app)** runs the full blocklist. Cloud users have no
#   legitimate reason to point Dawarich at RFC1918, CGNAT, loopback, or
#   ULA addresses; outbound traffic should always go to a routable public
#   address.
#
# - **Self-hosted** allows the typical homelab targets — RFC1918,
#   loopback, IPv6 ULA, etc. — because hitting `http://immich.lan/` or
#   `http://immich-server:2283` (Docker DNS) is the *normal* case. We
#   still apply the always-blocked tier (cloud metadata, multicast,
#   reserved, all-zero, link-local) and the basic well-formedness checks
#   so a fat-fingered `gopher://` or `http://169.254.169.254/` is still
#   caught.
#
# NOTE: this is a save-time check, not a request-time check. DNS rebinding
# is still possible: an attacker can serve a public IP to the validator
# and a private IP to the actual HTTPParty request a moment later. The
# mitigation lives in the HTTP client (pin the resolved IP) and is
# tracked separately. (audit C-3)
module UrlValidatable
  extend ActiveSupport::Concern

  class BlockedUrlError < StandardError; end

  # Blocked everywhere. Nothing in this list is a legitimate integration
  # target on either deployment topology.
  ALWAYS_BLOCKED_RANGES = [
    IPAddr.new('0.0.0.0/8'),       # invalid / "this network"
    IPAddr.new('169.254.0.0/16'),  # link-local + cloud metadata (AWS / GCP / OpenStack 169.254.169.254)
    IPAddr.new('224.0.0.0/4'),     # IPv4 multicast
    IPAddr.new('240.0.0.0/4'),     # IPv4 reserved
    IPAddr.new('fe80::/10'),       # IPv6 link-local (no scope-id support in URL form)
    IPAddr.new('ff00::/8')         # IPv6 multicast
  ].freeze

  # Additional ranges blocked on cloud only. Self-hosters routinely point
  # at these (Docker bridge networks, LAN, loopback, Tailscale CGNAT).
  CLOUD_ONLY_BLOCKED_RANGES = [
    IPAddr.new('10.0.0.0/8'),      # RFC1918
    IPAddr.new('100.64.0.0/10'),   # CGNAT (Tailscale uses this)
    IPAddr.new('127.0.0.0/8'),     # IPv4 loopback
    IPAddr.new('172.16.0.0/12'),   # RFC1918
    IPAddr.new('192.0.0.0/24'),    # IETF protocol assignments
    IPAddr.new('192.168.0.0/16'),  # RFC1918
    IPAddr.new('198.18.0.0/15'),   # benchmark
    IPAddr.new('::1/128'),         # IPv6 loopback
    IPAddr.new('fc00::/7')         # IPv6 ULA
  ].freeze

  private

  def validate_integration_url!(url)
    return if url.blank?

    uri = URI.parse(url)
    raise BlockedUrlError, "Invalid URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)
    raise BlockedUrlError, 'URL must include a host' if uri.host.blank?

    # Cloud refuses URLs that embed credentials. Self-hosters legitimately
    # use http://user:pass@host — homelab Immich behind nginx basic-auth
    # is a real config we don't want to break.
    if uri.userinfo.present? && !DawarichSettings.self_hosted?
      raise BlockedUrlError, 'URL must not embed credentials (user:pass@host)'
    end

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise BlockedUrlError, 'URL resolves to a blocked address' if blocked_ranges.any? { |range| range.include?(ip) }
  rescue URI::InvalidURIError
    raise BlockedUrlError, 'Invalid URL format'
  rescue Resolv::ResolvError
    raise BlockedUrlError, "Could not resolve hostname: #{uri.host}"
  end

  def blocked_ranges
    if DawarichSettings.self_hosted?
      ALWAYS_BLOCKED_RANGES
    else
      ALWAYS_BLOCKED_RANGES + CLOUD_ONLY_BLOCKED_RANGES
    end
  end
end
