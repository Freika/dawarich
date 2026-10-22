# frozen_string_literal: true

require 'rack/etag'

module Dawarich
  class SelectiveETag < Rack::ETag
    private

    def skip_caching?(headers)
      super || headers['content-type'].to_s.split(';', 2).first.to_s.strip.casecmp?('text/html')
    end
  end
end
