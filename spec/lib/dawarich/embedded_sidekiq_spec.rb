# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Embedded Sidekiq configuration' do
  around do |example|
    saved = ENV.to_h.slice('SIDEKIQ_EMBEDDED', 'BACKGROUND_PROCESSING_CONCURRENCY')
    ENV.delete('BACKGROUND_PROCESSING_CONCURRENCY')
    example.run
  ensure
    %w[SIDEKIQ_EMBEDDED BACKGROUND_PROCESSING_CONCURRENCY].each { |key| ENV.delete(key) }
    ENV.update(saved)
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

  it 'honors the background processing concurrency override' do
    ENV['BACKGROUND_PROCESSING_CONCURRENCY'] = '3'
    expect(Dawarich::EmbeddedSidekiq.build.config.concurrency).to eq(3)
  end
end
