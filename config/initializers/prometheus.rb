# in config/initializers/prometheus.rb
if Rails.env != "test" && ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true'
  require 'prometheus_exporter/middleware'
  require 'prometheus_exporter/instrumentation'

  # This reports stats per request like HTTP status and timings
  Rails.application.middleware.unshift PrometheusExporter::Middleware

    # this reports basic process stats like RSS and GC info, type master
  # means it is instrumenting the master process
  PrometheusExporter::Instrumentation::Process.start(type: "master")
end
