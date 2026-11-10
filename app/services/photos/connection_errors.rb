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

    # Integrations::Transport wraps what it raises; the raw classes stay for
    # the clients that still talk to the network themselves.
    RETRYABLE = (UNREACHABLE + [Net::OpenTimeout, Net::ReadTimeout,
                                Integrations::Transport::RetryableError]).freeze

    HANDLED = (RETRYABLE + [HTTParty::Error, JSON::ParserError, Integrations::Transport::Error]).freeze

    def self.retryable?(error)
      RETRYABLE.any? { |klass| error.is_a?(klass) }
    end
  end
end
