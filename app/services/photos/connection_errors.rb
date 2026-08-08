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

    HANDLED = ([
      HTTParty::Error,
      Net::OpenTimeout,
      Net::ReadTimeout,
      JSON::ParserError
    ] + UNREACHABLE).freeze
  end
end
