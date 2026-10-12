# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'Entrypoint development environment warning' do
  let(:guard_path) { File.expand_path('../../docker/entrypoint-env-guard.sh', __dir__) }

  def run_guard(env)
    script = "set -e; . #{guard_path}; warn_if_development_env; printf booted"
    base_env = { 'RAILS_ENV' => nil, 'RACK_ENV' => nil, 'SELF_HOSTED' => nil }
    Open3.capture3(base_env.merge(env), 'sh', '-c', script)
  end

  def expect_warning(env)
    stdout, stderr, status = run_guard(env)
    expect(stderr).to include('RAILS_ENV=production')
    expect(stdout).to eq('booted')
    expect(status).to be_success
  end

  def expect_silence(env)
    stdout, stderr, status = run_guard(env)
    expect(stderr).to be_empty
    expect(stdout).to eq('booted')
    expect(status).to be_success
  end

  it 'warns a self-hosted instance running in development' do
    expect_warning('RAILS_ENV' => 'development', 'SELF_HOSTED' => 'true')
  end

  it 'warns when neither RAILS_ENV nor RACK_ENV is set, as Rails then boots in development' do
    expect_warning({})
  end

  it 'warns when RAILS_ENV is empty' do
    expect_warning('RAILS_ENV' => '')
  end

  it 'follows RACK_ENV when RAILS_ENV is not set' do
    expect_silence('RACK_ENV' => 'production')
  end

  it 'prefers RAILS_ENV over RACK_ENV' do
    expect_silence('RAILS_ENV' => 'production', 'RACK_ENV' => 'development')
  end

  it 'stays silent in production' do
    expect_silence('RAILS_ENV' => 'production', 'SELF_HOSTED' => 'true')
  end

  it 'stays silent in staging' do
    expect_silence('RAILS_ENV' => 'staging')
  end

  ['1', 'TRUE', 'yes', 'On', 't', '"true"', "'true'", ' true '].each do |value|
    it "treats SELF_HOSTED=#{value.inspect} as self-hosted, like the app does" do
      expect_warning('RAILS_ENV' => 'development', 'SELF_HOSTED' => value)
    end
  end

  ['false', '0', 'no', ''].each do |value|
    it "stays silent when SELF_HOSTED=#{value.inspect}" do
      expect_silence('RAILS_ENV' => 'development', 'SELF_HOSTED' => value)
    end
  end

  it 'runs in both entrypoints after the privilege drop so the warning prints once' do
    %w[web-entrypoint.sh sidekiq-entrypoint.sh].each do |name|
      script = File.read(File.expand_path("../../docker/#{name}", __dir__))

      expect(script).to include("\nwarn_if_development_env\n")
      expect(script.index("\nwarn_if_development_env\n")).to be > script.index('exec gosu')
    end
  end
end
