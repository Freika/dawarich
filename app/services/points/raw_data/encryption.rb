# frozen_string_literal: true

module Points
  module RawData
    class Encryption
      SALT = 'points_raw_data_archive'
      KEY_LENGTH = 32 # AES-256-GCM

      class << self
        # Base64 encoding is required because MessageEncryptor uses JSON serialization
        # internally, which cannot handle binary gzip data (invalid UTF-8 sequences).
        def encrypt(data)
          encoded = Base64.strict_encode64(data)
          encryptor.encrypt_and_sign(encoded)
        end

        def decrypt(data)
          encoded = encryptor.decrypt_and_verify(data)
          Base64.strict_decode64(encoded)
        end

        # Decrypts content if the archive uses format_version >= 2 (encrypted).
        # Older archives (format_version 1) are plaintext gzip and returned as-is.
        def decrypt_if_needed(content, archive)
          format_version = archive.metadata&.dig('format_version').to_i
          return content unless format_version >= 2

          decrypt(content)
        end

        # Call after changing ARCHIVE_ENCRYPTION_KEY to clear the cached encryptor.
        def reset!
          @encryptor = nil
        end

        private

        def encryptor
          @encryptor ||= ActiveSupport::MessageEncryptor.new(derive_key)
        end

        def derive_key
          secret = ENV.fetch('ARCHIVE_ENCRYPTION_KEY') { Rails.application.secret_key_base }
          ActiveSupport::KeyGenerator.new(secret).generate_key(SALT, KEY_LENGTH)
        end
      end
    end
  end
end
