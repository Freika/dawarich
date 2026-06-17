# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Apple web sign-in initializer' do
  let(:valid_p8) do
    OpenSSL::PKey::EC.generate('prime256v1').to_pem
  end

  let(:base64_p8) { Base64.strict_encode64(valid_p8) }

  around do |example|
    original = defined?(APPLE_WEB_SIGN_IN_PRIVATE_KEY) ? APPLE_WEB_SIGN_IN_PRIVATE_KEY : nil
    example.run
  ensure
    Object.send(:remove_const, :APPLE_WEB_SIGN_IN_PRIVATE_KEY) if defined?(APPLE_WEB_SIGN_IN_PRIVATE_KEY)
    Object.const_set(:APPLE_WEB_SIGN_IN_PRIVATE_KEY, original) unless original.nil?
  end

  it 'exposes APPLE_WEB_SIGN_IN_PRIVATE_KEY when env is set' do
    stub_const('ENV', ENV.to_hash.merge('APPLE_WEB_P8_BASE64' => base64_p8))
    load Rails.root.join('config/initializers/04_apple_web_sign_in.rb')
    expect(APPLE_WEB_SIGN_IN_PRIVATE_KEY).to be_a(OpenSSL::PKey::EC)
  end

  it 'leaves APPLE_WEB_SIGN_IN_PRIVATE_KEY nil when env is blank' do
    stub_const('ENV', ENV.to_hash.except('APPLE_WEB_P8_BASE64'))
    load Rails.root.join('config/initializers/04_apple_web_sign_in.rb')
    expect(APPLE_WEB_SIGN_IN_PRIVATE_KEY).to be_nil
  end

  it 'raises at boot when env is set but malformed' do
    stub_const('ENV', ENV.to_hash.merge('APPLE_WEB_P8_BASE64' => Base64.strict_encode64('not a key')))
    expect { load Rails.root.join('config/initializers/04_apple_web_sign_in.rb') }
      .to raise_error(OpenSSL::PKey::ECError)
  end

  describe 'APPLE_WEB_SIGN_IN_ENABLED self-hosted gating' do
    around do |example|
      example.run
    ensure
      # ENV stub is reverted by this point; reload to restore the real boot values.
      load Rails.root.join('config/initializers/01_constants.rb')
    end

    let(:full_apple_env) do
      {
        'APPLE_WEB_SERVICES_ID' => 'app.dawarich.web',
        'APPLE_WEB_TEAM_ID' => 'TEAMID1234',
        'APPLE_WEB_KEY_ID' => 'KEYID12345',
        'APPLE_WEB_P8_BASE64' => 'base64data',
        'APPLE_WEB_REDIRECT_URI' => 'https://dawarich.app/users/auth/apple/callback'
      }
    end

    def reload_constants_with(env)
      stub_const('ENV', ENV.to_hash.merge(env))
      load Rails.root.join('config/initializers/01_constants.rb')
    end

    it 'is false on self-hosted even when all Apple env vars are present' do
      reload_constants_with(full_apple_env.merge('SELF_HOSTED' => 'true'))
      expect(APPLE_WEB_SIGN_IN_ENABLED).to be false
    end

    it 'is true on cloud when all Apple env vars are present' do
      reload_constants_with(full_apple_env.merge('SELF_HOSTED' => 'false'))
      expect(APPLE_WEB_SIGN_IN_ENABLED).to be true
    end

    it 'is false on cloud when an Apple env var is missing' do
      reload_constants_with(full_apple_env.except('APPLE_WEB_KEY_ID').merge('SELF_HOSTED' => 'false'))
      expect(APPLE_WEB_SIGN_IN_ENABLED).to be false
    end

    it 'is false on cloud when APPLE_WEB_REDIRECT_URI is missing' do
      reload_constants_with(full_apple_env.except('APPLE_WEB_REDIRECT_URI').merge('SELF_HOSTED' => 'false'))
      expect(APPLE_WEB_SIGN_IN_ENABLED).to be false
    end
  end
end
