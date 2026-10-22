# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'Dokploy production Compose deployment' do
  let(:compose) do
    YAML.safe_load_file(File.expand_path('../../compose.dokploy.production.yml', __dir__), aliases: true)
  end
  let(:services) { compose.fetch('services') }

  it 'runs migrations only through the release profile' do
    expect(services.fetch('release')).to include('profiles' => ['release'], 'command' => %w[rails db:migrate])
    expect(services.slice('web', 'worker').values).to all(satisfy { |service| !service.key?('profiles') })
  end

  it 'starts every process through the cloud entrypoint' do
    expect(services.values.map { |service| service['entrypoint'] }).to all(eq(['cloud-entrypoint.sh']))
  end

  it 'disables advisory locks for PgBouncer transaction pooling' do
    expect(services.values.map { |service| service.dig('environment', 'DATABASE_ADVISORY_LOCKS') }).to all(eq('false'))
  end

  it 'requires an explicit cron poll interval' do
    expect(services.dig('worker', 'environment', 'SIDEKIQ_CRON_POLL_INTERVAL'))
      .to start_with('${SIDEKIQ_CRON_POLL_INTERVAL:?')
  end

  it 'starts web and worker at zero replicas unless told otherwise' do
    expect(services.dig('web', 'deploy', 'replicas')).to eq('${WEB_REPLICAS:-0}')
    expect(services.dig('worker', 'deploy', 'replicas')).to eq('${WORKER_REPLICAS:-0}')
  end

  it 'points metrics at a worker alias unique on the shared network' do
    aliases = services.dig('worker', 'networks', 'dokploy-network', 'aliases')
    host = URI(services.dig('web', 'environment', 'SIDEKIQ_METRICS_URL')).host

    expect(aliases).to include(host)
    expect(host).not_to eq('worker')
  end
end
