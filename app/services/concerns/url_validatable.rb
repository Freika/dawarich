# frozen_string_literal: true

module UrlValidatable
  extend ActiveSupport::Concern

  class BlockedUrlError < StandardError; end

  BLOCKED_RANGES = [
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('169.254.0.0/16'),
    IPAddr.new('0.0.0.0/8'),
    IPAddr.new('::1/128'),
    IPAddr.new('fe80::/10')
  ].freeze

  private

  def validate_integration_url!(url)
    return if DawarichSettings.self_hosted?
    return if url.blank?

    uri = URI.parse(url)
    raise BlockedUrlError, "Invalid URL scheme: #{uri.scheme}" unless %w[http https].include?(uri.scheme)
    raise BlockedUrlError, 'URL must include a host' if uri.host.blank?

    ip = IPAddr.new(Resolv.getaddress(uri.host))
    raise BlockedUrlError, 'URL resolves to a blocked address' if BLOCKED_RANGES.any? { |range| range.include?(ip) }
  rescue URI::InvalidURIError
    raise BlockedUrlError, 'Invalid URL format'
  rescue Resolv::ResolvError
    raise BlockedUrlError, "Could not resolve hostname: #{uri.host}"
  end
end
