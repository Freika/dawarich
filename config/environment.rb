# frozen_string_literal: true

require 'opentelemetry/sdk' if ENV['SIGNOZ_MONITORING_ENABLED'] == 'true'
require_relative 'application'

OpenTelemetry::SDK.configure(&:use_all) if ENV['SIGNOZ_MONITORING_ENABLED'] == 'true'

Rails.application.initialize!
