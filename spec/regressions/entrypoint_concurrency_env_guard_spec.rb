# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'Entrypoint concurrency env guard' do
  let(:guard_path) { File.expand_path('../../docker/entrypoint-env-guard.sh', __dir__) }

  def run_guard(value)
    env = value.nil? ? {} : { 'WEB_CONCURRENCY' => value }
    script = ". #{guard_path}; sanitize_integer_env WEB_CONCURRENCY 1; printf '%s' \"${WEB_CONCURRENCY:-unset}\""
    Open3.capture3(env, 'sh', '-c', script)
  end

  it 'falls back to the default when the value is an unexpanded compose expression' do
    stdout, = run_guard('${WEB_CONCURRENCY:-1}')
    expect(stdout).to eq('1')
  end

  it 'warns about the invalid value' do
    _, stderr, = run_guard('${WEB_CONCURRENCY:-1}')
    expect(stderr).to include('not an integer')
  end

  it 'keeps a valid integer value untouched' do
    stdout, stderr, = run_guard('4')
    expect(stdout).to eq('4')
    expect(stderr).to be_empty
  end

  it 'keeps auto untouched' do
    stdout, stderr, = run_guard('auto')
    expect(stdout).to eq('auto')
    expect(stderr).to be_empty
  end

  it 'leaves an unset variable unset' do
    stdout, = run_guard(nil)
    expect(stdout).to eq('unset')
  end

  it 'is wired into both entrypoints' do
    web = File.read(File.expand_path('../../docker/web-entrypoint.sh', __dir__))
    sidekiq = File.read(File.expand_path('../../docker/sidekiq-entrypoint.sh', __dir__))

    expect(web).to include('entrypoint-env-guard.sh')
    expect(web).to include('sanitize_integer_env WEB_CONCURRENCY')
    expect(sidekiq).to include('entrypoint-env-guard.sh')
    expect(sidekiq).to include('sanitize_integer_env BACKGROUND_PROCESSING_CONCURRENCY')
  end
end
