# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dawarich::Application.env_or_dev_default' do
  def call_resolver(var, fallback)
    Dawarich::Application.env_or_dev_default(var, fallback)
  end

  let(:otp_vars) do
    %w[OTP_ENCRYPTION_PRIMARY_KEY
       OTP_ENCRYPTION_DETERMINISTIC_KEY
       OTP_ENCRYPTION_KEY_DERIVATION_SALT]
  end

  context 'in production' do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    context 'with SECRET_KEY_BASE present and the env var missing' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('SECRET_KEY_BASE').and_return('a' * 64)
        allow(ENV).to receive(:[]).with('SECRET_KEY_BASE_DUMMY').and_return(nil)
      end

      it 'derives a non-empty key for each OTP variable' do
        otp_vars.each do |env_var|
          allow(ENV).to receive(:[]).with(env_var).and_return(nil)

          derived = call_resolver(env_var, 'unused')

          expect(derived).to be_a(String)
          expect(derived.length).to be >= 32
          expect(derived).not_to eq('unused')
        end
      end

      it 'derives different keys for different variables' do
        otp_vars.each { |v| allow(ENV).to receive(:[]).with(v).and_return(nil) }

        derived = otp_vars.map { |v| call_resolver(v, 'unused') }

        expect(derived.uniq.length).to eq(otp_vars.length)
      end

      it 'derives stable keys across calls' do
        allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return(nil)

        first = call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'unused')
        second = call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'unused')

        expect(first).to eq(second)
      end

      it 'derives different keys for different SECRET_KEY_BASE values' do
        allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('SECRET_KEY_BASE').and_return('a' * 64)
        first = call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'unused')

        allow(ENV).to receive(:[]).with('SECRET_KEY_BASE').and_return('b' * 64)
        second = call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'unused')

        expect(first).not_to eq(second)
      end
    end

    context 'with SECRET_KEY_BASE absent and the env var missing' do
      it 'raises for each OTP variable' do
        otp_vars.each do |env_var|
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with(env_var).and_return(nil)
          allow(ENV).to receive(:[]).with('SECRET_KEY_BASE').and_return(nil)
          allow(ENV).to receive(:[]).with('SECRET_KEY_BASE_DUMMY').and_return(nil)

          expect { call_resolver(env_var, 'unused') }
            .to raise_error(RuntimeError, /#{env_var} required in production/)
        end
      end
    end

    context 'when the env var is set' do
      it 'returns the env value (never the dev fallback or the derived value)' do
        otp_vars.each do |env_var|
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with(env_var).and_return('prod-value')

          expect(call_resolver(env_var, 'dev-fallback')).to eq('prod-value')
        end
      end
    end

    context 'with SECRET_KEY_BASE_DUMMY set' do
      it 'returns the dev fallback (asset compilation path)' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('SECRET_KEY_BASE_DUMMY').and_return('1')

        expect(call_resolver('OTP_ENCRYPTION_PRIMARY_KEY', 'dev-fallback')).to eq('dev-fallback')
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
