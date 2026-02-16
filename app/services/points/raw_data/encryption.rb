# frozen_string_literal: true

module Points
  module RawData
    class Encryption
      SALT = 'points_raw_data_archive'
      KEY_LENGTH = 32 # AES-256-GCM

      class << self
        def encrypt(data)
          encoded = Base64.strict_encode64(data)
          encryptor.encrypt_and_sign(encoded)
        end

        def decrypt(data)
          encoded = encryptor.decrypt_and_verify(data)
          Base64.strict_decode64(encoded).force_encoding(Encoding::ASCII_8BIT)
        end

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
