# frozen_string_literal: true

module Photos
  module ConnectionErrors
    UNREACHABLE = [
      SocketError,
      Resolv::ResolvError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::EPIPE,
      EOFError,
      Net::HTTPBadResponse,
      OpenSSL::SSL::SSLError
    ].freeze

    RETRYABLE = (UNREACHABLE + [Net::OpenTimeout, Net::ReadTimeout]).freeze

    HANDLED = (RETRYABLE + [HTTParty::Error, JSON::ParserError]).freeze

    def self.retryable?(error)
      RETRYABLE.any? { |klass| error.is_a?(klass) }
    end
  end
end
