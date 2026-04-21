# frozen_string_literal: true

require 'rails_helper'

# Verifies that config/application.rb enforces OTP encryption keys in production.
#
# We can't reload config/application.rb in-process (Rails doesn't permit it),
# so we exercise the exact guard expression used in the file. If the file is
# ever refactored away from this pattern, this spec will also need updating —
# which is the intended coupling: the guard is security-critical.
RSpec.describe 'Active Record encryption key enforcement' do
  # Mirrors the expression in config/application.rb exactly.
  def resolve_key(env_var, fallback:)
    ENV[env_var] ||
      (Rails.env.production? ? raise("#{env_var} required in production") : fallback)
  end

  context 'in production' do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
    end

    %w[OTP_ENCRYPTION_PRIMARY_KEY
       OTP_ENCRYPTION_DETERMINISTIC_KEY
       OTP_ENCRYPTION_KEY_DERIVATION_SALT].each do |env_var|
      it "raises when #{env_var} is missing" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with(env_var).and_return(nil)

        expect { resolve_key(env_var, fallback: 'unused') }
          .to raise_error(RuntimeError, /#{env_var} required in production/)
      end

      it "returns the value when #{env_var} is set" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with(env_var).and_return('prod-value')

        expect(resolve_key(env_var, fallback: 'unused')).to eq('prod-value')
      end
    end

    it 'matches the actual guard pattern in config/application.rb' do
      source = Rails.root.join('config/application.rb').read

      %w[OTP_ENCRYPTION_PRIMARY_KEY
         OTP_ENCRYPTION_DETERMINISTIC_KEY
         OTP_ENCRYPTION_KEY_DERIVATION_SALT].each do |env_var|
        expect(source).to match(
          /ENV\['#{env_var}'\].*?Rails\.env\.production\?.*?raise\(['"]#{env_var} required in production['"]\)/m
        )
      end
    end
  end

  context 'in development' do
    before do
      allow(Rails.env).to receive(:production?).and_return(false)
    end

    it 'falls back to the dev placeholder when the env var is missing' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OTP_ENCRYPTION_PRIMARY_KEY').and_return(nil)

      expect(resolve_key('OTP_ENCRYPTION_PRIMARY_KEY', fallback: 'dev-fallback'))
        .to eq('dev-fallback')
    end
  end
end
