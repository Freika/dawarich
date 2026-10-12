# frozen_string_literal: true

module ReverseGeocoding
  module ProviderErrors
    UNREACHABLE = [Errno::ECONNREFUSED, SocketError].freeze

    TRANSIENT = ([
      Geocoder::LookupTimeout,
      Geocoder::NetworkError,
      Geocoder::ServiceUnavailable,
      Geocoder::ResponseParseError
    ] + UNREACHABLE).freeze

    SEARCH_HANDLED = (TRANSIENT + [Geocoder::InvalidRequest]).freeze

    TRANSIENT_TLS_MESSAGE = 'unexpected eof while reading'

    def self.transient_tls?(error)
      error.is_a?(OpenSSL::SSL::SSLError) && error.message.include?(TRANSIENT_TLS_MESSAGE)
    end
  end
end
