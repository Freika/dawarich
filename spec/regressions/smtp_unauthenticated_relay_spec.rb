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
