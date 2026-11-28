# frozen_string_literal: true

module Points
  module RawData
    class Encryption
      SALT = 'points_raw_data_archive'
      KEY_LENGTH = 32 # AES-256-GCM

      class KeyNotConfigured < StandardError
        def initialize(msg = 'ARCHIVE_ENCRYPTION_KEY must be set in production before raw data is archived. ' \
                             'If this instance already has archives, set it to the current SECRET_KEY_BASE value ' \
                             'so they keep the same key; otherwise generate one with `bin/rails secret`.')
          super
        end
      end

      class << self
        # Base64 encoding is required because MessageEncryptor uses JSON serialization
        # internally, which cannot handle binary gzip data (invalid UTF-8 sequences).
        def encrypt(data)
          ensure_key_configured!

          encoded = Base64.strict_encode64(data)
          encryptor.encrypt_and_sign(encoded)
        end

        def decrypt(data)
          Base64.strict_decode64(decrypt_and_verify(data))
        end

        # Decrypts content if the archive uses format_version >= 2 (encrypted).
        # Older archives (format_version 1) are plaintext gzip and returned as-is.
        def decrypt_if_needed(content, archive)
          format_version = archive.metadata&.dig('format_version').to_i
          return content unless format_version >= 2

          decrypt(content)
        end

        # A SECRET_KEY_BASE-derived key is only acceptable outside production:
        # rotating SECRET_KEY_BASE would make every archive unreadable, and
        # cleared raw_data has no other copy.
        def key_configured?
          explicit_key.present? || !Rails.env.production?
        end

        def ensure_key_configured!
          raise KeyNotConfigured unless key_configured?
        end

        # Call after changing ARCHIVE_ENCRYPTION_KEY to clear the cached encryptors.
        def reset!
          @encryptor = nil
          @legacy_encryptor = nil
        end

        private

        def decrypt_and_verify(data)
          encryptor.decrypt_and_verify(data)
        rescue ActiveSupport::MessageEncryptor::InvalidMessage
          raise unless explicit_key

          # Archives written before ARCHIVE_ENCRYPTION_KEY was set used SECRET_KEY_BASE.
          legacy_encryptor.decrypt_and_verify(data)
        end

        def encryptor
          @encryptor ||= build_encryptor(explicit_key || Rails.application.secret_key_base)
        end

        def legacy_encryptor
          @legacy_encryptor ||= build_encryptor(Rails.application.secret_key_base)
        end

        # Not .presence: an instance that ran with an empty value encrypted with
        # that empty key, and its archives must stay readable.
        def explicit_key
          ENV.fetch('ARCHIVE_ENCRYPTION_KEY', nil)
        end

        def build_encryptor(secret)
          key = ActiveSupport::KeyGenerator.new(secret).generate_key(SALT, KEY_LENGTH)
          ActiveSupport::MessageEncryptor.new(key)
        end
      end
    end
  end
end
