# frozen_string_literal: true

require 'socket'

module PrometheusHelper
  CONNECT_TIMEOUT = 3 # seconds per attempt
  MAX_RETRIES = 3
  RETRY_DELAY = 2 # seconds between retries

  class << self
    # Checks if the Prometheus exporter host is reachable.
    # For remote hosts, retries a few times to handle startup race conditions
    # (e.g. Dokku where the exporter container may still be booting).
    # Caches the result for the lifetime of the process.
    def ensure_reachable!
      return @reachable if defined?(@reachable)

      host = ENV.fetch('PROMETHEUS_EXPORTER_HOST', 'localhost')
      port = ENV.fetch('PROMETHEUS_EXPORTER_PORT', 9394).to_i

      @reachable = reachable_with_retries?(host, port)

      if @reachable
        Rails.logger.info "Prometheus exporter reachable at #{host}:#{port}" if defined?(Rails)
      else
        warn_unreachable(host, port)
      end

      @reachable
    end

    # Reset cached state (useful for testing)
    def reset!
      remove_instance_variable(:@reachable) if defined?(@reachable)
    end

    private

    def reachable_with_retries?(host, port)
      # For local/embedded exporter addresses, assume reachable since the entrypoint
      # starts the exporter process alongside the app
      return true if local_address?(host)

      # For remote hosts, retry to handle startup race conditions
      MAX_RETRIES.times do |attempt|
        return true if tcp_reachable?(host, port)

        if attempt < MAX_RETRIES - 1
          log_retry(host, port, attempt + 1)
          sleep RETRY_DELAY
        end
      end

      false
    end

    def tcp_reachable?(host, port)
      socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
      sockaddr = Socket.sockaddr_in(port, host)
      socket.connect_nonblock(sockaddr)
      true
    rescue IO::WaitWritable
      # Connection in progress, wait with timeout
      if IO.select(nil, [socket], nil, CONNECT_TIMEOUT)
        # Verify the connection actually succeeded (not just writable due to error)
        socket.connect_nonblock(sockaddr)
        true
      else
        false
      end
    rescue Errno::EISCONN
      # Already connected — IO.select returned and connect_nonblock confirms success
      true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
           Errno::ETIMEDOUT, SocketError, Errno::EADDRNOTAVAIL
      false
    ensure
      socket&.close
    end

    def local_address?(host)
      %w[localhost 127.0.0.1 0.0.0.0 :: ANY].include?(host) || host.nil? || host.empty?
    end

    def log_retry(host, port, attempt)
      message = "[Prometheus] Exporter at #{host}:#{port} not ready, " \
                "retrying (#{attempt}/#{MAX_RETRIES - 1})..."

      if defined?(Rails) && Rails.logger
        Rails.logger.info message
      else
        warn message
      end
    end

    def warn_unreachable(host, port)
      message = "[Prometheus] Exporter at #{host}:#{port} is not reachable " \
                "after #{MAX_RETRIES} attempts. " \
                'Metrics collection is disabled for this process. ' \
                'Ensure the exporter is running and the host is accessible.'

      if defined?(Rails) && Rails.logger
        Rails.logger.warn message
      else
        warn message
      end
    end
  end
end
