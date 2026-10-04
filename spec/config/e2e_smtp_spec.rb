# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'E2E stack SMTP configuration' do
  it 'uses the configured SMTP sink only when the stack explicitly opts in' do
    mailer = Rails.application.config.action_mailer
    original = mailer.to_h
    base = ENV.to_h.except('E2E_PROXY_STACK', 'E2E_SMTP_DELIVERY').merge(
      'SMTP_SERVER' => '127.0.0.2', 'E2E_SMTP_PORT' => '1225'
    )

    [
      [{}, :test],
      [{ 'E2E_PROXY_STACK' => '1' }, :test],
      [{ 'E2E_SMTP_DELIVERY' => '1' }, :test],
      [{ 'E2E_PROXY_STACK' => '1', 'E2E_SMTP_DELIVERY' => '0' }, :test],
      [{ 'E2E_PROXY_STACK' => '1', 'E2E_SMTP_DELIVERY' => '1' }, :smtp]
    ].each do |flags, expected|
      stub_const('ENV', base.merge(flags))
      load Rails.root.join('config/environments/test.rb')
      expect(mailer.delivery_method).to eq(expected)
      next unless expected == :smtp

      expect(mailer.smtp_settings).to eq(address: '127.0.0.2', port: 1225, enable_starttls_auto: false)
      expect(mailer.raise_delivery_errors).to be(true)
    end
  ensure
    mailer.clear
    mailer.merge!(original)
  end
end
