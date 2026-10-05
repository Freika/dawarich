# frozen_string_literal: true

module FixtureRecording
  module DeterministicInputs
    def self.included(base)
      base.include ActiveSupport::Testing::TimeHelpers
      base.around do |example|
        models = fixture_models
        first = 20_000_000 + (Digest::MD5.hexdigest(example.full_description).to_i(16) % 100_000) * 10_000
        counters = models.index_with { first }
        models.each do |model|
          connection = ActiveRecord::Base.connection
          sequence = connection.select_value("SELECT pg_get_serial_sequence('#{model.table_name}', 'id')")
          connection.execute("SELECT setval('#{sequence}', #{first + 1}, false)") if sequence
        end
        pin = lambda do |row|
          row.id ||= counters[row.class] += 1
          row.visits_redetected_at ||= Time.current if row.is_a?(User)
        end
        models.each { _1.before_validation(pin, on: :create) }
        FactoryBot.rewind_sequences
        FFaker::Random.seed = 1153
        travel_to(Time.utc(2026, 10, 5, 12)) { example.run }
      ensure
        models&.each { _1.skip_callback(:validation, :before, pin) }
      end
      base.before do
        random = Random.new(1153)
        allow(SecureRandom).to receive(:random_bytes) { |n| random.bytes(n || 16) }
        allow(OpenSSL::Random).to receive(:random_bytes) { |n| random.bytes(n) }
        allow_any_instance_of(OpenSSL::Cipher).to receive(:random_iv) do |cipher|
          cipher.iv = random.bytes(cipher.iv_len)
        end
        allow(Rack::Utils).to receive(:clock_time).and_return(0.0)
      end
    end
  end

  def self.verify(path, bytes)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    else
      raise "#{path} differs from Rails" unless File.binread(path) == bytes.b
    end
  end
end
