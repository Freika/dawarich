# frozen_string_literal: true

require 'sidekiq/web'

module Dawarich
  class SidekiqWeb < Sidekiq::Web
    def safe_request?(env)
      return true if super
      return false if env.key?('HTTP_SEC_FETCH_SITE')

      env['HTTP_ORIGIN'] == Rack::Request.new(env).base_url
    end
  end
end
