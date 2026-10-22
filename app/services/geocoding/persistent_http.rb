# frozen_string_literal: true

module Geocoding
  class PersistentHttp
    THREAD_KEY = :geocoding_http_connection

    module Lookup
      private

      def http_client
        PersistentHttp.new(super)
      end
    end

    def self.reset!
      _key, connection = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = nil
      connection.finish if connection&.started?
    rescue IOError, SystemCallError
      nil
    end

    def initialize(client)
      @client = client
    end

    def start(host, port, use_ssl:, open_timeout:, read_timeout:)
      key = [@client.proxy_address, @client.proxy_port, @client.proxy_user, @client.proxy_pass,
             host, port, use_ssl, open_timeout, read_timeout]
      completed = false
      response = yield(checkout(key, host, port, use_ssl, open_timeout, read_timeout))
      completed = true
      response
    ensure
      self.class.reset! unless completed
    end

    private

    def checkout(key, host, port, use_ssl, open_timeout, read_timeout)
      cached_key, connection = Thread.current[THREAD_KEY]
      return connection if cached_key == key

      self.class.reset!
      connection = @client.new(host, port).tap do |http|
        http.use_ssl = use_ssl
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout
        http.start
      end
      Thread.current[THREAD_KEY] = [key, connection]
      connection
    end
  end
end
