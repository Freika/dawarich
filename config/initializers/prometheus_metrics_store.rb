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

multiproc_dir = Rails.root.join('tmp/prometheus_mmap').to_s
FileUtils.mkdir_p(multiproc_dir)

# Wipe stale files from prior process lifetimes — but ONLY for PIDs no longer
# alive. Blanket-wipe corrupts metrics in workers that are still serving
# traffic during a Puma rolling restart.
Dir.glob(File.join(multiproc_dir, '*.db')).each do |path|
  pid = File.basename(path)[/_(\d+)\.db\z/, 1]&.to_i
  next unless pid # unknown naming pattern — leave it alone

  begin
    Process.kill(0, pid) # signal 0 = existence probe
    # process still alive — keep its file
  rescue Errno::ESRCH
    File.unlink(path) # process gone — safe to remove
  rescue Errno::EPERM
    # process exists but we can't signal it; assume alive
  end
end

Prometheus::Client.config.data_store =
  Prometheus::Client::DataStores::DirectFileStore.new(dir: multiproc_dir)

Rails.logger.info "[Prometheus] DirectFileStore initialized at #{multiproc_dir}" if defined?(Rails.logger)
