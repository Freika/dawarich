# frozen_string_literal: true

module B12E2EEgress
  def self.enabled?
    ENV['E2E_B12_EGRESS'] == '1'
  end

  def self.install!
    return unless enabled?

    require 'webmock'
    WebMock.enable!
    WebMock.disable_net_connect!(allow: ->(uri) { %w[127.0.0.1 ::1].include?(uri.host) })
    ActionMailer::Base.raise_delivery_errors = true
  end
end

B12E2EEgress.install!
