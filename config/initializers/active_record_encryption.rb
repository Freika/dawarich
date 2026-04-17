# frozen_string_literal: true

# Active Record Encryption is required by devise-two-factor for the `encrypts :otp_secret`
# declaration on the User model. These keys must always be set for the model to load.
#
# 2FA is only user-facing when all three env vars are explicitly set (checked via
# DawarichSettings.two_factor_available?). Without them, the 2FA settings page is hidden
# and the OTP login challenge is skipped — but the model still needs encryption keys to boot.
Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch('OTP_ENCRYPTION_PRIMARY_KEY', 'dawarich-dev-primary-key-not-for-production')
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch('OTP_ENCRYPTION_DETERMINISTIC_KEY', 'dawarich-dev-deterministic-not-for-prod')
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch('OTP_ENCRYPTION_KEY_DERIVATION_SALT', 'dawarich-dev-salt-not-for-production')
