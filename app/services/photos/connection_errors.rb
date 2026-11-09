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

    HANDLED = (RETRYABLE + [JSON::ParserError, Integrations::Transport::Error]).freeze

    def self.retryable?(error)
      RETRYABLE.any? { |klass| error.is_a?(klass) }
    end

    def self.certificate?(error)
      error.is_a?(OpenSSL::SSL::SSLError) ||
        (error.is_a?(Integrations::Transport::Error) && error.certificate?)
    end

    # Worth raising to a caller that asked for connection errors: a failure a
    # retry may fix, or one the transport refused outright (redirect, blocked
    # address), which the user has to hear about.
    def self.reportable?(error)
      retryable?(error) || error.is_a?(Integrations::Transport::Error)
    end

    # What a user-facing message should say. A transport error already carries
    # a readable message (the redirect hint, the DNS text); for anything else
    # the class name is the most specific thing available.
    def self.describe(error)
      error.is_a?(Integrations::Transport::Error) ? error.message : error.class.name
    end
  end
end
