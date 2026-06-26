# frozen_string_literal: true

require 'rails_helper'
require 'smtp_config'

RSpec.describe SmtpConfig do
  describe '.smtp_settings' do
    it 'maps SMTP_* env vars onto the action_mailer smtp_settings hash' do
      env = {
        'SMTP_SERVER'   => 'smtp.office365.com',
        'SMTP_PORT'     => '587',
        'SMTP_DOMAIN'   => 'example.com',
        'SMTP_USERNAME' => 'noreply@example.com',
        'SMTP_PASSWORD' => 'secret'
      }

      result = described_class.smtp_settings(env)

      expect(result).to include(
        address:   'smtp.office365.com',
        port:      587,
        domain:    'example.com',
        user_name: 'noreply@example.com',
        password:  'secret'
      )
    end

    it 'casts SMTP_PORT to integer so the Mail gem picks the right TLS mode for SMTPS-on-465' do
      expect(described_class.smtp_settings('SMTP_PORT' => '465')[:port]).to eq(465)
    end

    it 'leaves port nil when SMTP_PORT is unset' do
      expect(described_class.smtp_settings({})[:port]).to be_nil
    end

    it 'defaults authentication to :plain when SMTP_AUTHENTICATION is unset' do
      expect(described_class.smtp_settings({})[:authentication]).to eq(:plain)
    end

    it 'casts SMTP_AUTHENTICATION to a symbol from the Mail-gem-supported whitelist' do
      %w[plain login cram_md5 digest_md5 gssapi ntlm xoauth2].each do |value|
        expect(
          described_class.smtp_settings('SMTP_AUTHENTICATION' => value)[:authentication]
        ).to eq(value.to_sym)
      end
    end

    it 'treats an empty SMTP_AUTHENTICATION as the :plain default (back-compat)' do
      expect(described_class.smtp_settings('SMTP_AUTHENTICATION' => '')[:authentication]).to eq(:plain)
      expect(described_class.smtp_settings('SMTP_AUTHENTICATION' => '   ')[:authentication]).to eq(:plain)
    end

    it 'rejects truly unsupported SMTP_AUTHENTICATION values at boot rather than at SMTP-connect time' do
      expect do
        described_class.smtp_settings('SMTP_AUTHENTICATION' => 'oauth1')
      end.to raise_error(ArgumentError, /SMTP_AUTHENTICATION/)
    end

    it 'enables STARTTLS by default and respects SMTP_STARTTLS=false' do
      expect(described_class.smtp_settings({})[:enable_starttls]).to be(true)
      expect(described_class.smtp_settings('SMTP_STARTTLS' => 'false')[:enable_starttls]).to be(false)
    end

    it 'defaults timeouts to 5 seconds and accepts overrides' do
      expect(described_class.smtp_settings({})).to include(open_timeout: 5, read_timeout: 5)
      expect(
        described_class.smtp_settings('SMTP_OPEN_TIMEOUT' => '25', 'SMTP_READ_TIMEOUT' => '30')
      ).to include(open_timeout: 25, read_timeout: 30)
    end

    it 'falls back to the 5-second default when a timeout env var is set but blank' do
      expect(
        described_class.smtp_settings('SMTP_OPEN_TIMEOUT' => '', 'SMTP_READ_TIMEOUT' => '   ')
      ).to include(open_timeout: 5, read_timeout: 5)
    end

    it 'defaults openssl_verify_mode to VERIFY_PEER so certificates are validated' do
      expect(described_class.smtp_settings({})[:openssl_verify_mode]).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it 'sets openssl_verify_mode to VERIFY_NONE when SMTP_IGNORE_CERT_ERRORS=true' do
      expect(
        described_class.smtp_settings('SMTP_IGNORE_CERT_ERRORS' => 'true')[:openssl_verify_mode]
      ).to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'keeps VERIFY_PEER for SMTP_IGNORE_CERT_ERRORS=false' do
      expect(
        described_class.smtp_settings('SMTP_IGNORE_CERT_ERRORS' => 'false')[:openssl_verify_mode]
      ).to eq(OpenSSL::SSL::VERIFY_PEER)
    end
  end

  describe '.mailer_url_options' do
    it 'reads DOMAIN as host and always uses https' do
      expect(
        described_class.mailer_url_options('DOMAIN' => 'dawarich.example')
      ).to eq(host: 'dawarich.example', protocol: 'https')
    end

    it 'ignores APPLICATION_PROTOCOL so reverse-proxy operators with force_ssl=off still get https links' do
      expect(
        described_class.mailer_url_options('DOMAIN' => 'cloud.example', 'APPLICATION_PROTOCOL' => 'http')
      ).to eq(host: 'cloud.example', protocol: 'https')
    end
  end
end
