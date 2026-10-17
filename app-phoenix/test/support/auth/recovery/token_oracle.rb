# frozen_string_literal: true

require_relative 'oracle_support'

generator = Devise.token_generator.instance_variable_get(:@key_generator).instance_variable_get(:@key_generator)
raws = ['reset-fixture_12345', '', " \t", 160.chr(Encoding::UTF_8)]
cases = %i[reset_password_token unlock_token].flat_map do |column|
  raws.map { |raw| { column:, raw:, digest: Devise.token_generator.digest(User, column, raw) } }
end

RecoveryOracle.write(
  ARGV.fetch(0),
  iterations: generator.instance_variable_get(:@iterations),
  kdf_digest: generator.instance_variable_get(:@hash_digest_class).name,
  cases:
)
puts 'Captured Devise recovery token digests'
