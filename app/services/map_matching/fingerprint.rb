# frozen_string_literal: true

require 'digest'

module MapMatching
  module Fingerprint
    def self.call(input)
      Digest::SHA256.hexdigest(JSON.generate(input.fingerprint_payload))
    end
  end
end
