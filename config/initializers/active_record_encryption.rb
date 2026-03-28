# frozen_string_literal: true

# Active Record Encryption is required by devise-two-factor for encrypting OTP secrets.
# Keys can be overridden via environment variables. Defaults are provided for development
# and self-hosted instances that don't set custom keys — production deployments SHOULD
# set unique values via OTP_ENCRYPTION_PRIMARY_KEY, OTP_ENCRYPTION_DETERMINISTIC_KEY,
# and OTP_ENCRYPTION_KEY_DERIVATION_SALT.
Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch('OTP_ENCRYPTION_PRIMARY_KEY', 'dawarich-otp-primary-key-change-me')
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch('OTP_ENCRYPTION_DETERMINISTIC_KEY', 'dawarich-otp-deterministic-key-change')
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch('OTP_ENCRYPTION_KEY_DERIVATION_SALT', 'dawarich-otp-key-derivation-salt-ch')
