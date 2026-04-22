# frozen_string_literal: true

require 'ipaddr'
require 'resolv'

module Webhooks
  class UrlValidator
    PRIVATE_RANGES = [
      IPAddr.new('10.0.0.0/8'),
      IPAddr.new('172.16.0.0/12'),
      IPAddr.new('192.168.0.0/16'),
      IPAddr.new('127.0.0.0/8'),
      IPAddr.new('169.254.0.0/16'),
      IPAddr.new('::1/128'),
      IPAddr.new('fc00::/7'),
      IPAddr.new('fe80::/10')
    ].freeze

    def self.call(url)
      uri = URI.parse(url)
      return :invalid_format unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return :ok if DawarichSettings.self_hosted?
      return :invalid_scheme unless uri.scheme == 'https'
      return :private_address if private_host?(uri.host)

      :ok
    rescue URI::InvalidURIError, Resolv::ResolvError
      :invalid_format
    end

    def self.private_host?(host)
      return true if host == 'localhost'

      addresses = resolve(host)
      return true if addresses.empty?

      addresses.any? do |addr|
        ip = begin
          IPAddr.new(addr)
        rescue StandardError
          nil
        end
        next false unless ip

        PRIVATE_RANGES.any? { |range| range.include?(ip) }
      end
    end

    def self.resolve(host)
      # If host is already a literal IP, return it as-is (avoid DNS)
      IPAddr.new(host)
      [host]
    rescue IPAddr::InvalidAddressError
      Resolv.getaddresses(host)
    end
  end
end
