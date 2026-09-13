# frozen_string_literal: true

require 'rails_helper'
require 'dawarich/aggregating_metrics'
require 'rack/mock'

RSpec.describe 'Merged /metrics never repeats a label set' do
  let(:local_body) { <<~METRICS }
    # HELP sidekiq_jobs_enqueued_total Total enqueued
    # TYPE sidekiq_jobs_enqueued_total counter
    sidekiq_jobs_enqueued_total{queue="visit_suggesting",worker="VisitSuggestingJob"} 19.0
    # HELP activerecord_connection_pool_size Pool size
    # TYPE activerecord_connection_pool_size gauge
    activerecord_connection_pool_size 5.0
    # HELP rails_requests_total Total HTTP requests
    # TYPE rails_requests_total counter
    rails_requests_total{controller="home"} 5
  METRICS

  let(:remote_body) { <<~METRICS }
    # HELP sidekiq_jobs_enqueued_total Total enqueued
    # TYPE sidekiq_jobs_enqueued_total counter
    sidekiq_jobs_enqueued_total{queue="visit_suggesting",worker="VisitSuggestingJob"} 23.0
    # HELP activerecord_connection_pool_size Pool size
    # TYPE activerecord_connection_pool_size gauge
    activerecord_connection_pool_size 12.0
    # HELP sidekiq_jobs_executed_total Total executed
    # TYPE sidekiq_jobs_executed_total counter
    sidekiq_jobs_executed_total{queue="default"} 12
  METRICS

  let(:local_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, [local_body]] } }

  let(:middleware) do
    Dawarich::AggregatingMetrics.new(
      local_app,
      remote_url: 'http://sidekiq.internal:9394/metrics',
      remote_user: 'prometheus',
      remote_password: 'secret'
    )
  end

  before do
    stub_request(:get, 'http://sidekiq.internal:9394/metrics')
      .with(basic_auth: %w[prometheus secret])
      .to_return(status: 200, body: remote_body)
  end

  def merged_output
    _status, _headers, body = middleware.call(Rack::MockRequest.env_for('/metrics'))
    body.each.to_a.join
  end

  # Mirrors the reporter's own detection: strip comments, strip each line's
  # value, then look for a repeated name+labels combination.
  def repeated_series(output)
    identities = output.each_line
                       .reject { |line| line.start_with?('#') }
                       .map(&:strip)
                       .reject(&:empty?)
                       .map { |line| line.sub(/\s+\S+\s*\z/, '') }

    identities.tally.select { |_identity, count| count > 1 }.keys
  end

  it 'emits no repeated name+label-set combination' do
    expect(repeated_series(merged_output)).to be_empty
  end

  it 'keeps both processes values rather than dropping one' do
    output = merged_output

    expect(output).to include('19.0')
    expect(output).to include('23.0')
    expect(output).to include('5.0')
    expect(output).to include('12.0')
  end

  it 'distinguishes the colliding samples by originating process' do
    output = merged_output

    expect(output).to match(/sidekiq_jobs_enqueued_total\{[^}]*process="web"[^}]*\} 19\.0/)
    expect(output).to match(/sidekiq_jobs_enqueued_total\{[^}]*process="sidekiq"[^}]*\} 23\.0/)
  end

  it 'labels a colliding sample that had no labels at all' do
    output = merged_output

    expect(output).to include('activerecord_connection_pool_size{process="web"} 5.0')
    expect(output).to include('activerecord_connection_pool_size{process="sidekiq"} 12.0')
  end

  it 'leaves samples that appear on only one side untouched' do
    output = merged_output

    expect(output).to include('rails_requests_total{controller="home"} 5')
    expect(output).to include('sidekiq_jobs_executed_total{queue="default"} 12')
    expect(output).not_to match(/rails_requests_total\{[^}]*process=/)
  end

  context 'with label shapes that resemble the process label' do
    let(:local_body) { %(collides{subprocess="a"} 5.0\n) }
    let(:remote_body) { %(collides{subprocess="a"} 9.0\n) }

    it 'still disambiguates when another label merely ends in "process"' do
      output = merged_output

      expect(repeated_series(output)).to be_empty
      expect(output).to include('process="web"')
      expect(output).to include('process="sidekiq"')
    end
  end

  context 'when a sample already carries a process label' do
    let(:local_body) { %(already{process="web"} 5.0\n) }
    let(:remote_body) { %(already{process="web"} 9.0\n) }

    it 'leaves it alone rather than nesting a second process label' do
      expect(merged_output.scan('process=').size).to eq(2)
    end
  end

  context 'when one side writes an empty label set explicitly' do
    let(:local_body) { %(bare 5.0\n) }
    let(:remote_body) { %(bare{} 9.0\n) }

    it 'treats the bare name and the empty label set as the same series' do
      expect(repeated_series(merged_output)).to be_empty
    end
  end

  context 'when a label value contains a closing brace' do
    let(:local_body) { %(braced{path="}"} 5.0\n) }
    let(:remote_body) { %(braced{path="}"} 9.0\n) }

    it 'splits the label set from the value correctly' do
      output = merged_output

      expect(repeated_series(output)).to be_empty
      expect(output).to include(%(braced{process="web",path="}"} 5.0))
    end
  end

  context 'when a body has no trailing newline' do
    let(:local_body) { %(first{a="1"} 5.0) }
    let(:remote_body) { %(second{b="2"} 9.0\n) }

    it 'does not glue the two bodies into one malformed line' do
      expect(merged_output).to eq(%(first{a="1"} 5.0\nsecond{b="2"} 9.0\n))
    end
  end

  it 'still deduplicates HELP and TYPE metadata' do
    output = merged_output

    expect(output.scan('# TYPE sidekiq_jobs_enqueued_total counter').size).to eq(1)
    expect(output.scan('# HELP sidekiq_jobs_enqueued_total Total enqueued').size).to eq(1)
  end
end
