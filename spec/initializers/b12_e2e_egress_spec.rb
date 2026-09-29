# frozen_string_literal: true

require 'rails_helper'

RSpec.describe B12E2EEgress do
  around do |example|
    webmock = WebMock::Config.instance
    webmock_state = %i[allow_net_connect allow_localhost allow net_http_connect_on_start]
                    .index_with { |key| webmock.public_send(key) }
    mailer_errors = ActionMailer::Base.raise_delivery_errors
    sidekiq_level = Sidekiq.default_configuration.logger.level
    cron_enabled = Sidekiq::Cron.configuration.enabled
    example.run
  ensure
    webmock_state.each { |key, value| webmock.public_send("#{key}=", value) }
    ActionMailer::Base.raise_delivery_errors = mailer_errors
    Sidekiq.default_configuration.logger.level = sidekiq_level
    Sidekiq::Cron.configuration.enabled = cron_enabled
  end

  def opt_in(value = '1')
    stub_const('ENV', ENV.to_h.merge('E2E_B12_EGRESS' => value))
  end

  it 'allows only loopback HTTP, fails on SMTP errors and quiets Sidekiq when opted in' do
    opt_in
    WebMock.allow_net_connect!
    ActionMailer::Base.raise_delivery_errors = false
    Sidekiq.default_configuration.logger.level = Logger::INFO
    Sidekiq::Cron.configuration.enabled = true

    described_class.install!

    expect(WebMock.net_connect_allowed?(URI('http://127.0.0.1:3103/health'))).to be(true)
    expect(WebMock.net_connect_allowed?(URI('https://example.invalid/'))).to be(false)
    expect(ActionMailer::Base.raise_delivery_errors).to be(true)
    expect(Sidekiq.default_configuration.logger.level).to eq(Logger::WARN)
    expect(Sidekiq::Cron.configuration.enabled).to be(false)
  end

  it 'leaves outbound HTTP alone without the opt-in' do
    opt_in('0')
    WebMock.allow_net_connect!

    described_class.install!

    expect(WebMock.net_connect_allowed?(URI('https://example.invalid/'))).to be(true)
  end

  it 'refuses to boot in production' do
    opt_in
    allow(Rails.env).to receive(:production?).and_return(true)
    WebMock.allow_net_connect!

    expect { described_class.install! }.to raise_error(RuntimeError, /must never be set in production/)
    expect(WebMock.net_connect_allowed?(URI('https://example.invalid/'))).to be(true)
  end
end
