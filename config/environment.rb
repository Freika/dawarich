# frozen_string_literal: true

require 'opentelemetry/sdk'
require_relative 'application'

OpenTelemetry::SDK.configure do |c|
  c.use_all
end

Rails.application.initialize!
