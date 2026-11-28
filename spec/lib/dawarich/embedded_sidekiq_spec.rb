# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Embedded Sidekiq configuration' do
  around do |example|
    saved = ENV.to_h.slice('SIDEKIQ_EMBEDDED', 'BACKGROUND_PROCESSING_CONCURRENCY')
    broadcasts = Rails.logger.broadcasts.dup
    ENV.delete('BACKGROUND_PROCESSING_CONCURRENCY')
    example.run
  ensure
    %w[SIDEKIQ_EMBEDDED BACKGROUND_PROCESSING_CONCURRENCY].each { |key| ENV.delete(key) }
    ENV.update(saved)
    (Rails.logger.broadcasts - broadcasts).each { |logger| Rails.logger.stop_broadcasting_to(logger) }
  end

  it 'keeps embedding opt in' do
    ENV.delete('SIDEKIQ_EMBEDDED')
    expect(Dawarich::EmbeddedSidekiq.enabled?).to be(false)
    ENV['SIDEKIQ_EMBEDDED'] = 'false'
    expect(Dawarich::EmbeddedSidekiq.enabled?).to be(false)
    ENV['SIDEKIQ_EMBEDDED'] = 'true'
    expect(Dawarich::EmbeddedSidekiq.enabled?).to be(true)
  end

  it 'defaults to two embedded threads and consumes every configured queue' do
    instance = Dawarich::EmbeddedSidekiq.build
    config = instance.config
    expect(config.concurrency).to eq(2)
    queues = YAML.load_file(Rails.root.join('config/sidekiq.yml'))[:queues]
    expect(config.queues).to eq(queues)
    expect(Sidekiq::Queue['reverse_geocoding'].limit).to eq(1)
    expect(config[:reloader]).to be_a(Sidekiq::Rails::Reloader)
  end

  it 'logs at the configured Rails log level, even when a broadcast logs more' do
    log_level = Rails.configuration.log_level
    sidekiq_logger = Sidekiq.default_configuration.logger
    Rails.configuration.log_level = 'warn'
    Rails.logger.broadcast_to(Logger.new(File::NULL, level: :info))

    logger = Dawarich::EmbeddedSidekiq.build.config.logger

    expect(logger.level).to eq(Logger::WARN)
    expect { logger.info('embedded-sidekiq-info') }.not_to output.to_stdout_from_any_process
  ensure
    Rails.configuration.log_level = log_level
    Sidekiq.default_configuration.logger = sidekiq_logger
  end

  it 'honors the background processing concurrency override' do
    ENV['BACKGROUND_PROCESSING_CONCURRENCY'] = '3'
    expect(Dawarich::EmbeddedSidekiq.build.config.concurrency).to eq(3)
  end
end
