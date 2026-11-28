# frozen_string_literal: true

require 'rack/etag'

module Dawarich
  class SelectiveEtag < Rack::ETag
    private

    def skip_caching?(headers)
      super || headers['content-type'].to_s.split(';', 2).first.to_s.strip.casecmp?('text/html')
    end
  end
end

Rails.application.config.middleware.swap Rack::ETag, Dawarich::SelectiveEtag, 'no-cache'
