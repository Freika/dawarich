# frozen_string_literal: true

# Initialize Prometheus exporter for web processes, but exclude console, rake tasks, and tests
should_initialize = DawarichSettings.prometheus_exporter_enabled? &&
                    !Rails.env.test? &&
                    !defined?(Rails::Console) &&
                    !File.basename($PROGRAM_NAME).include?('rake')

if should_initialize
  require 'prometheus_exporter/middleware'
  require 'prometheus_exporter/instrumentation'

  # This reports stats per request like HTTP status and timings
  Rails.application.middleware.unshift PrometheusExporter::Middleware

  # This reports basic process stats like RSS and GC info
  PrometheusExporter::Instrumentation::Process.start(type: 'web')

  # Add ActiveRecord instrumentation
  PrometheusExporter::Instrumentation::ActiveRecord.start
end
