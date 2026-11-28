# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe 'Scraping metrics with the configured multi-process store', type: :request do
  around do |example|
    previous_store = Prometheus::Client.config.data_store
    previous_exporter = Yabeda::Prometheus::Exporter.instance_variable_get(:@app)
    Yabeda::Prometheus::Exporter.instance_variable_set(:@app, nil)
    factory_dir = Rails.root.join('tmp/factory')
    FileUtils.mkdir_p(factory_dir)

    Dir.mktmpdir('metrics-scrape-', factory_dir) do |directory|
      @metrics_root = Pathname.new(directory)
      example.run
    end
  ensure
    Prometheus::Client.config.data_store = previous_store
    Yabeda::Prometheus::Exporter.instance_variable_set(:@app, previous_exporter)
  end

  it 'returns Prometheus text without crashing when reading persisted metric labels' do
    initializer = Rails.root.join('config/initializers/prometheus_metrics_store.rb')
    allow(DawarichSettings).to receive(:prometheus_exporter_enabled?).and_return(true)

    RSpec::Mocks.with_temporary_scope do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))
      allow(Rails).to receive(:root).and_return(@metrics_root)
      allow(Sidekiq).to receive(:server?).and_return(false)
      load initializer
    end

    registry = Prometheus::Client::Registry.new
    counter = registry.counter(:synthetic_scrapes_total, docstring: 'Synthetic scrapes', labels: [:source])
    counter.increment(labels: { source: 'made up & synthetic' }, by: 3)
    allow(Yabeda::Prometheus).to receive(:registry).and_return(registry)
    allow(Yabeda).to receive(:collect!)
    stub_request(:get, %r{/metrics\z}).to_return(status: 200, body: '')

    expect do
      get '/metrics', headers: {
        'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(
          METRICS_USERNAME, METRICS_PASSWORD
        )
      }
    end.not_to raise_error

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with('text/plain')
    expect(response.body).to include('synthetic_scrapes_total{source="made up & synthetic"} 3.0')
  end
end
