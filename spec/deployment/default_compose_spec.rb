# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'Default Compose deployment' do
  let(:compose) { YAML.safe_load_file(File.expand_path('../../docker/docker-compose.yml', __dir__)) }
  let(:app) { compose.fetch('services').fetch('dawarich_app') }

  it 'runs embedded jobs in a single Puma process by default' do
    expect(app.fetch('environment')).to include('SIDEKIQ_EMBEDDED' => 'true', 'WEB_CONCURRENCY' => '0')
    expect(app.fetch('command')).to eq(['bin/rails', 'server', '-p', '3000', '-b', '::'])
  end

  it 'defaults to two background threads with an environment override' do
    expect(app.fetch('environment').fetch('BACKGROUND_PROCESSING_CONCURRENCY'))
      .to eq('${BACKGROUND_PROCESSING_CONCURRENCY:-2}')
  end

  it 'allows embedded jobs sixty seconds to drain' do
    expect(app['stop_grace_period']).to eq('60s')
  end

  it 'ships one application service without a standalone worker or override' do
    expect(compose.fetch('services').keys).to match_array(%w[dawarich_app dawarich_db dawarich_redis])
    expect(File).not_to exist(File.expand_path('../../docker/docker-compose.embedded.yml', __dir__))
  end
end
