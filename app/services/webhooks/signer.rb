# frozen_string_literal: true

module Webhooks
  class Signer
    def self.sign(body:, secret:)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    end
  end
end
