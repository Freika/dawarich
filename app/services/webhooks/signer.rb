# frozen_string_literal: true

module Webhooks
  class Signer
    def self.sign(body:, secret:)
      digest = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      "sha256=#{digest}"
    end
  end
end
