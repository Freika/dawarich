# frozen_string_literal: true

require 'rails_helper'
require 'smtp_config'

RSpec.describe SmtpConfig do
  describe '.smtp_settings for unauthenticated relays' do
    it 'disables authentication when SMTP_AUTHENTICATION expresses no auth' do
      %w[none nil off false disabled NONE None Off].each do |value|
        expect(
          described_class.smtp_settings('SMTP_AUTHENTICATION' => value)[:authentication]
        ).to be_nil
      end
    end

    it 'keeps a local unauthenticated relay usable with no username or password' do
      settings = described_class.smtp_settings(
        'SMTP_SERVER' => 'localhost',
        'SMTP_PORT' => '25',
        'SMTP_AUTHENTICATION' => 'none'
      )

      expect(settings[:authentication]).to be_nil
      expect(settings[:user_name]).to be_nil
      expect(settings[:password]).to be_nil
    end

    it 'does not warn when SMTP_AUTHENTICATION is none and no credentials are present' do
      expect do
        described_class.smtp_settings('SMTP_AUTHENTICATION' => 'none')
      end.not_to output.to_stderr
    end

    it 'does not warn when SMTP_AUTHENTICATION is none and credentials are blank (.env.example default)' do
      expect do
        described_class.smtp_settings(
          'SMTP_USERNAME' => '',
          'SMTP_PASSWORD' => '   ',
          'SMTP_AUTHENTICATION' => 'none'
        )
      end.not_to output.to_stderr
    end

    context 'when SMTP_AUTHENTICATION=none is combined with populated credentials' do
      it 'clears user_name and password so net-smtp cannot fall back to AUTH PLAIN' do
        %w[none nil off false disabled NONE None Off].each do |value|
          settings = described_class.smtp_settings(
            'SMTP_USERNAME' => 'leftover_user',
            'SMTP_PASSWORD' => 'leftover_pw',
            'SMTP_AUTHENTICATION' => value
          )

          expect(settings[:authentication]).to be_nil
          expect(settings[:user_name]).to be_nil, "SMTP_AUTHENTICATION=#{value} should clear user_name"
          expect(settings[:password]).to be_nil, "SMTP_AUTHENTICATION=#{value} should clear password"
        end
      end

      it 'warns on stderr that the leftover credentials are being ignored' do
        expect do
          described_class.smtp_settings(
            'SMTP_USERNAME' => 'leftover_user',
            'SMTP_PASSWORD' => 'leftover_pw',
            'SMTP_AUTHENTICATION' => 'none'
          )
        end.to output(
          %r{SMTP_AUTHENTICATION=none ignores SMTP_USERNAME/SMTP_PASSWORD.*clearing them to disable AUTH}m
        ).to_stderr
      end
    end

    it 'does not warn when an auth mechanism is configured with credentials' do
      expect do
        described_class.smtp_settings(
          'SMTP_USERNAME' => 'noreply@example.com',
          'SMTP_PASSWORD' => 'secret',
          'SMTP_AUTHENTICATION' => 'plain'
        )
      end.not_to output.to_stderr
    end

    it 'still rejects genuinely unsupported authentication values' do
      expect do
        described_class.smtp_settings('SMTP_AUTHENTICATION' => 'oauth1')
      end.to raise_error(ArgumentError, /SMTP_AUTHENTICATION/)
    end

    it 'still defaults to :plain when SMTP_AUTHENTICATION is unset' do
      expect(described_class.smtp_settings({})[:authentication]).to eq(:plain)
    end
  end
end
