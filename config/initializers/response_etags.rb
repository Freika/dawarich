# frozen_string_literal: true

require_relative '../../lib/dawarich/selective_etag'

Rails.application.config.middleware.swap Rack::ETag, Dawarich::SelectiveETag, 'no-cache'
