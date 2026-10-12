# frozen_string_literal: true

APPLE_WEB_SIGN_IN_PRIVATE_KEY =
  (OpenSSL::PKey::EC.new(Base64.decode64(ENV['APPLE_WEB_P8_BASE64'])) if ENV['APPLE_WEB_P8_BASE64'].present?)
