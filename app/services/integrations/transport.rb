# frozen_string_literal: true

require 'net/http'

module Integrations
  # The one outbound HTTP path for user-configured integrations (Immich,
  # Photoprism, AirTrail, TeslaMate, TREK).
  #
  # Every request re-validates the URL against UrlValidatable, connects to the
  # address that was validated (so a DNS answer cannot change between the check
  # and the connect), never follows a redirect, and always has a timeout.
  #
  # Any answer that is not a redirect comes back as a Response, including 4xx
  # and 5xx; callers decide what those mean. Everything else raises Error.
  class Transport
    include UrlValidatable

    DEFAULT_TIMEOUT = 10
    REQUEST_CLASSES = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.freeze

    # Raised for a refused address and for a refused redirect.
    class Error < StandardError
      attr_reader :status

      def initialize(message = nil, status: nil, blocked: false, unresolvable: false)
        super(message)
        @status = status
        @blocked = blocked
        @unresolvable = unresolvable
      end

      def blocked? = @blocked
      def unresolvable? = @unresolvable
      def certificate? = cause.is_a?(OpenSSL::SSL::SSLError)
      def retryable? = false
    end

    # Raised when the request could not be completed: host not resolving, no
    # connection, TLS failure, timeout. Trying again later may work.
    class RetryableError < Error
      def retryable? = true
    end

    # Case-insensitive view of the response headers.
    class Headers
      def initialize(http_response)
        @values = http_response.to_hash.transform_values { |values| values.join(', ') }
      end

      def [](name) = @values[name.to_s.downcase]
      def to_h = @values.dup
    end

    Response = Struct.new(:code, :body, :headers) do
      def success? = code.between?(200, 299)
    end

    def self.request(method, url, **options)
      new(method, url, **options).call
    end

    def initialize(method, url, headers: {}, query: nil, body: nil, skip_ssl_verification: false,
                   timeout: DEFAULT_TIMEOUT)
      @request_class = REQUEST_CLASSES.fetch(method) { raise ArgumentError, "Unsupported HTTP method: #{method}" }
      @url = url.to_s
      @headers = headers
      @query = query
      @body = body
      @skip_ssl_verification = ActiveModel::Type::Boolean.new.cast(skip_ssl_verification) || false
      @timeout = timeout
    end

    def call
      addresses = validated_addresses
      uri = request_uri
      response = try_addresses(uri, addresses)
      refuse_redirect(response) if response.is_a?(Net::HTTPRedirection)

      Response.new(response.code.to_i, response.body.to_s, Headers.new(response))
    rescue OpenSSL::SSL::SSLError, SystemCallError, IOError, Timeout::Error, SocketError,
           Resolv::ResolvError, Net::HTTPBadResponse, Net::ProtocolError => e
      raise RetryableError, e.message
    end

    private

    def validated_addresses
      resolve_integration_addresses!(@url) || raise(Error.new('Integration URL is missing', blocked: true))
    rescue UrlValidatable::BlockedUrlError => e
      # An unresolvable host is reported through the same error class as a
      # blocked one; only a real range block is final.
      raise RetryableError.new(e.message, unresolvable: true) if e.cause.is_a?(SocketError)

      raise Error.new(e.message, blocked: true)
    end

    def request_uri
      uri = URI.parse(@url)
      extra = URI.encode_www_form(@query.compact) if @query.present?
      uri.query = [uri.query, extra].compact_blank.join('&').presence
      uri
    end

    # Tries each validated address in turn, so a host with an unreachable
    # first record (often an unrouted AAAA) still connects on the next.
    def try_addresses(uri, addresses)
      last_error = nil
      addresses.each do |address|
        return perform(uri, address)
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL,
             Net::OpenTimeout => e
        last_error = e
      end
      raise last_error
    end

    def perform(uri, address)
      http = connection(uri)
      # Behind a proxy the target is resolved by the proxy, so there is nothing to pin.
      return http.start { |open| open.request(build_request(uri)) } if http.proxy?

      http.ipaddr = address
      http.start { |open| open.request(build_request(uri)) }
    end

    def connection(uri)
      # Two-argument form keeps HTTP_PROXY / NO_PROXY from the environment.
      Net::HTTP.new(uri.hostname, uri.port).tap do |http|
        http.use_ssl = uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl? && @skip_ssl_verification
        http.open_timeout = @timeout
        http.read_timeout = @timeout
        http.write_timeout = @timeout
      end
    end

    def build_request(uri)
      request = @request_class.new(uri.request_uri, @headers.transform_keys(&:to_s))
      request.body = @body if @body
      # Same precedence HTTParty had: credentials in the URL win over a
      # caller's Authorization header (a homelab reverse proxy in front).
      request.basic_auth(*uri.userinfo.split(':', 2)) if uri.userinfo.present?
      request
    end

    def refuse_redirect(response)
      target = begin
        URI.parse(response['location'].to_s).host
      rescue URI::InvalidURIError
        nil
      end
      hint = target ? " to #{target}" : ''

      raise Error.new("The server answered with a redirect#{hint} (HTTP #{response.code}). " \
                      'Save the final URL instead.', status: response.code.to_i)
    end
  end
end
