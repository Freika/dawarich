# frozen_string_literal: true

module Geocoding
  class PersistentHttp
    THREAD_KEY = :geocoding_http_connections

    module Lookup
      private

      def http_client
        PersistentHttp.new(super)
      end
    end

    def self.reset!
      Thread.current[THREAD_KEY]&.each_value { |connection| connection.finish if connection.started? }
      Thread.current[THREAD_KEY] = nil
    end

    def initialize(client)
      @client = client
    end

    def start(host, port, use_ssl:, open_timeout:, read_timeout:)
      key = [@client.proxy_address, @client.proxy_port, @client.proxy_user, @client.proxy_pass,
             host, port, use_ssl, open_timeout, read_timeout]
      connections = Thread.current[THREAD_KEY] ||= {}
      yield(connections[key] ||= connect(host, port, use_ssl, open_timeout, read_timeout))
    end

    private

    def connect(host, port, use_ssl, open_timeout, read_timeout)
      @client.new(host, port).tap do |http|
        http.use_ssl = use_ssl
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.start
      end
    end
  end
end
