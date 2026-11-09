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

    # What a user-facing message may say. Text written by this app (the
    # redirect hint, a refused or unresolvable address) is shown as it is.
    # Text from the network stack or the remote server is not: it can echo a
    # credential, so only the class of the failure is named.
    def self.describe(error)
      return error.class.name unless error.is_a?(Integrations::Transport::Error)
      return error.message if error.cause.nil? || error.cause.is_a?(UrlValidatable::BlockedUrlError)

      error.cause.class.name
    end
  end
end
