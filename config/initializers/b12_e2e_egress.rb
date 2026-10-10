# frozen_string_literal: true

module B12E2EEgress
  def self.enabled?
    ENV['E2E_B12_EGRESS'] == '1'
  end

  def self.install!
    return unless enabled?
    raise 'E2E_B12_EGRESS=1 blocks all outbound HTTP and must never be set in production' if Rails.env.production?

    require 'webmock'
    WebMock.enable!
    WebMock.disable_net_connect!(allow: ->(uri) { %w[127.0.0.1 ::1].include?(uri.host) })
    ActionMailer::Base.raise_delivery_errors = true
    Sidekiq.default_configuration.logger.level = Logger::WARN
    Sidekiq::Cron.configuration.enabled = false
  end
end

B12E2EEgress.install!
