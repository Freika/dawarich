# frozen_string_literal: true

if defined?(Rails::Server) && !Rails.env.test? && DawarichSettings.prometheus_exporter_enabled?
  require 'prometheus_exporter/middleware'
  require 'prometheus_exporter/instrumentation'

  # This reports stats per request like HTTP status and timings
  Rails.application.middleware.unshift PrometheusExporter::Middleware

  # This reports basic process stats like RSS and GC info
  PrometheusExporter::Instrumentation::Process.start(type: 'web')

  # Add ActiveRecord instrumentation
  PrometheusExporter::Instrumentation::ActiveRecord.start
end
