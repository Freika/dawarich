# frozen_string_literal: true

require 'rails_helper'
require 'dawarich/aggregating_metrics'
require 'rack/mock'

RSpec.describe Dawarich::AggregatingMetrics do
  let(:local_body) { <<~METRICS }
    # HELP rails_requests_total Total HTTP requests
    # TYPE rails_requests_total counter
    rails_requests_total{controller="home"} 5
  METRICS

  let(:remote_body) { <<~METRICS }
    # HELP sidekiq_jobs_executed_total Total Sidekiq jobs
    # TYPE sidekiq_jobs_executed_total counter
    sidekiq_jobs_executed_total{queue="default"} 12
  METRICS

  let(:local_app) do
    ->(_env) { [200, { 'Content-Type' => 'text/plain' }, [local_body]] }
  end

  let(:middleware) do
    described_class.new(
      local_app,
      remote_url: 'http://sidekiq.internal:9394/metrics',
      remote_user: 'prometheus',
      remote_password: 'secret'
    )
  end

  def request(env_overrides = {})
    env = Rack::MockRequest.env_for('/metrics', env_overrides)
    middleware.call(env)
  end

  describe 'when remote endpoint responds with metrics' do
    before do
      stub_request(:get, 'http://sidekiq.internal:9394/metrics')
        .with(basic_auth: %w[prometheus secret])
        .to_return(status: 200, body: remote_body)
    end

    it 'returns 200 with concatenated bodies' do
      status, headers, body = request
      out = body.each.to_a.join
      expect(status).to eq(200)
      expect(headers['Content-Type']).to start_with('text/plain')
      expect(out).to include('rails_requests_total{controller="home"} 5')
      expect(out).to include('sidekiq_jobs_executed_total{queue="default"} 12')
    end

    it 'deduplicates HELP and TYPE lines for the same metric name across sources' do
      duplicate_remote = local_body + remote_body
      stub_request(:get, 'http://sidekiq.internal:9394/metrics')
        .with(basic_auth: %w[prometheus secret])
        .to_return(status: 200, body: duplicate_remote)

      _status, _headers, body = request
      out = body.each.to_a.join
      expect(out.scan('# HELP rails_requests_total').size).to eq(1)
      expect(out.scan('# TYPE rails_requests_total').size).to eq(1)
    end
  end

  describe 'when remote endpoint is unreachable' do
    before do
      stub_request(:get, 'http://sidekiq.internal:9394/metrics')
        .to_raise(Errno::ECONNREFUSED)
    end

    it 'returns 200 with local metrics only and logs a warning' do
      expect(Rails.logger).to receive(:warn).with(/sidekiq/)
      status, _headers, body = request
      out = body.each.to_a.join
      expect(status).to eq(200)
      expect(out).to include('rails_requests_total')
      expect(out).not_to include('sidekiq_jobs_executed_total')
    end
  end

  describe 'when remote endpoint returns non-200' do
    before do
      stub_request(:get, 'http://sidekiq.internal:9394/metrics')
        .to_return(status: 503, body: 'unavailable')
    end

    it 'returns 200 with local metrics only and logs a warning' do
      expect(Rails.logger).to receive(:warn).with(/503/)
      status, _headers, body = request
      out = body.each.to_a.join
      expect(status).to eq(200)
      expect(out).to include('rails_requests_total')
      expect(out).not_to include('unavailable')
    end
  end

  describe 'when local app returns non-200' do
    let(:local_app) { ->(_env) { [404, {}, ['']] } }

    it 'passes through without fetching remote' do
      status, _headers, _body = request
      expect(status).to eq(404)
      expect(WebMock).not_to have_requested(:get, 'http://sidekiq.internal:9394/metrics')
    end
  end
end
