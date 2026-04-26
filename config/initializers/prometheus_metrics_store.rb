# frozen_string_literal: true

# Configure prometheus-client's data store for Puma multi-worker aggregation.
# Web workers write to mmap'd files in a shared directory; GET /metrics reads
# and aggregates across them.
#
# Skipped in:
#   - test env (we use RSpec matchers against the in-memory registry)
#   - rake tasks (one-shot, no aggregation needed)
#   - Rails console (interactive, no metrics server)
#   - Sidekiq server process (threaded, uses in-memory store)
return if Rails.env.test?
return if defined?(Rails::Console)
return if File.basename($PROGRAM_NAME).include?('rake')
return if defined?(Sidekiq) && Sidekiq.server?
return unless DawarichSettings.prometheus_exporter_enabled?

require 'prometheus/client'
require 'prometheus/client/data_stores/direct_file_store'

multiproc_dir = ENV.fetch('PROMETHEUS_MULTIPROC_DIR', Rails.root.join('tmp/prometheus_mmap').to_s)
FileUtils.mkdir_p(multiproc_dir)

# Wipe stale files from prior process lifetimes so we never read garbage.
Dir.glob(File.join(multiproc_dir, '*.db')).each { |f| File.unlink(f) }

Prometheus::Client.config.data_store =
  Prometheus::Client::DataStores::DirectFileStore.new(dir: multiproc_dir)

Rails.logger.info "[Prometheus] DirectFileStore initialized at #{multiproc_dir}" if defined?(Rails.logger)
