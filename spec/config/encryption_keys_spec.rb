# frozen_string_literal: true

require 'rails_helper'

# Verifies the encryption-key resolver used during Rails bootstrap to populate
# `config.active_record.encryption.*`. The resolver is defined as a class
# method on Dawarich::Application so config/application.rb can call it before
# any initializer runs.
RSpec.describe 'Dawarich::Application.env_or_dev_default' do
  def call_resolver(var, fallback)
    Dawarich::Application.env_or_dev_default(var, fallback)
  end

  context 'in production' do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    %w[OTP_ENCRYPTION_PRIMARY_KEY
       OTP_ENCRYPTION_DETERMINISTIC_KEY
       OTP_ENCRYPTION_KEY_DERIVATION_SALT].each do |env_var|
      it "raises when #{env_var} is missing" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with(env_var).and_return(nil)

        expect { call_resolver(env_var, 'unused') }
          .to raise_error(RuntimeError, /#{env_var} required in production/)
      end

      it "returns the env value when #{env_var} is set (never the dev fallback)" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with(env_var).and_return('prod-value')

        expect(call_resolver(env_var, 'dev-fallback')).to eq('prod-value')
      end
    end
  end

  context 'in development' do
    before { allow(Rails.env).to receive(:production?).and_return(false) }

    it 'falls back to the dev placeholder when the env var is missing' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return(nil)

      expect(call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'dev-fallback')).to eq('dev-fallback')
    end

    it 'prefers the env value over the dev fallback when both are present' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return('explicit-value')

      expect(call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'dev-fallback')).to eq('explicit-value')
    end
  end
end
