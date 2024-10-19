# frozen_string_literal: true

# This code fixes failed to get urandom for running Ruby on Docker for Synology.
class Random
  class << self
    private

    # :stopdoc:

    # Implementation using OpenSSL
    def gen_random_openssl(n)
      OpenSSL::Random.random_bytes(n)
    end

    begin
      # Check if Random.urandom is available
      Random.urandom(1)
    rescue RuntimeError
      begin
        require 'openssl'
      rescue NoMethodError
        raise NotImplementedError, 'No random device'
      else
        alias urandom gen_random_openssl
      end
    end

    public :urandom
  end
end
