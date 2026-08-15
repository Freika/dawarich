# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmtpConfig do
  describe '.smtp_settings' do
    let(:base_env) do
      {
        'SMTP_SERVER' => 'mail.example.com',
        'SMTP_DOMAIN' => 'example.com',
        'SMTP_USERNAME' => 'user',
        'SMTP_PASSWORD' => 'secret'
      }
    end

    context 'when SMTP_SSL is enabled' do
      let(:env) { base_env.merge('SMTP_PORT' => '2465', 'SMTP_SSL' => 'true') }

      it 'uses implicit TLS and disables STARTTLS' do
        settings = described_class.smtp_settings(env)

        expect(settings[:ssl]).to be(true)
        expect(settings[:enable_starttls]).to be(false)
      end
    end

    context 'when SMTP_PORT is 465 and SMTP_SSL is not set' do
      let(:env) { base_env.merge('SMTP_PORT' => '465') }

      it 'defaults to implicit TLS so the connection does not hang in STARTTLS' do
        settings = described_class.smtp_settings(env)

        expect(settings[:ssl]).to be(true)
        expect(settings[:enable_starttls]).to be(false)
      end
    end

    context 'when SMTP_SSL is explicitly disabled on port 465' do
      let(:env) { base_env.merge('SMTP_PORT' => '465', 'SMTP_SSL' => 'false') }

      it 'respects the override' do
        settings = described_class.smtp_settings(env)

        expect(settings[:ssl]).to be(false)
        expect(settings[:enable_starttls]).to be(true)
      end
    end

    context 'when using a STARTTLS provider (port 587)' do
      let(:env) { base_env.merge('SMTP_PORT' => '587') }

      it 'keeps the existing STARTTLS behavior' do
        settings = described_class.smtp_settings(env)

        expect(settings[:ssl]).to be(false)
        expect(settings[:enable_starttls]).to be(true)
      end
    end
  end
end
