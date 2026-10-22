# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sentry initializer' do
  let(:log) { Struct.new(:attributes, :body).new({ 'token' => 'secret' }, 'Signed in as user@example.com') }

  def load_initializer(env = {})
    stub_const('SENTRY_DSN', 'https://public@o0.ingest.example.invalid/1')
    stub_const('ENV', ENV.to_hash.except('SENTRY_ENABLE_LOGS').merge(env))
    load Rails.root.join('config/initializers/sentry.rb')
  end

  def sentry_log_broadcasts
    Rails.logger.broadcasts.grep(SentryLogsLogger)
  end

  after do
    sentry_log_broadcasts.each { |logger| Rails.logger.stop_broadcasting_to(logger) }
    Sentry.close if Sentry.initialized?
  end

  context 'when SENTRY_ENABLE_LOGS is not set' do
    before { load_initializer }

    it 'initializes Sentry' do
      expect(Sentry.initialized?).to be true
    end

    it 'drops logs before they are sent' do
      expect(Sentry.configuration.before_send_log.call(log)).to be_nil
    end

    it 'does not forward Rails logs to Sentry' do
      expect(sentry_log_broadcasts).to be_empty
    end

    it 'keeps Rails structured logging off' do
      expect(Sentry.configuration.rails.structured_logging.enabled?).to be false
    end
  end

  context 'when SENTRY_ENABLE_LOGS is true' do
    before { load_initializer('SENTRY_ENABLE_LOGS' => 'true') }

    it 'redacts logs before they are sent' do
      sent = Sentry.configuration.before_send_log.call(log)

      expect(sent.attributes['token']).to eq('[FILTERED]')
      expect(sent.body).to eq('Signed in as [EMAIL]')
    end

    it 'forwards Rails logs to Sentry' do
      expect(sentry_log_broadcasts.size).to eq(1)
    end

    it 'keeps Rails structured logging off' do
      expect(Sentry.configuration.rails.structured_logging.enabled?).to be false
    end
  end
end
