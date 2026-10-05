# frozen_string_literal: true

module FixtureRecording
  SECRET = 'phoenix-a2-cookie-fixture-secret-not-for-production'

  module SyntheticSecret
    def self.included(base)
      base.around do |example|
        app = Rails.application
        previous = app.config.secret_key_base
        env = app.env_config.slice('action_dispatch.secret_key_base', 'action_dispatch.key_generator')
        turbo_key = Turbo.signed_stream_verifier_key
        turbo_verifier = Turbo::StreamsChannel.instance_variable_get(:@signed_stream_verifier)
        app.config.secret_key_base = SECRET
        app.env_config.merge!('action_dispatch.secret_key_base' => SECRET,
                              'action_dispatch.key_generator' => app.key_generator)
        Turbo.signed_stream_verifier_key = app.key_generator.generate_key('turbo/signed_stream_verifier_key')
        Turbo::StreamsChannel.remove_instance_variable(:@signed_stream_verifier) if turbo_verifier
        example.run
      ensure
        app.config.secret_key_base = previous
        app.env_config.merge!(env)
        Turbo.signed_stream_verifier_key = turbo_key
        Turbo::StreamsChannel.instance_variable_set(:@signed_stream_verifier, turbo_verifier)
      end
    end
  end

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
    bytes = normalize(bytes)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    else
      raise "#{path} differs from Rails" unless File.binread(path) == bytes.b
    end
  end

  def self.normalize(value)
    case value
    when Hash then value.transform_values { normalize(_1) }
    when Array then value.map { normalize(_1) }
    when String then normalize_text(value)
    else value
    end
  end

  def self.normalize_text(text)
    Gem.loaded_specs.each_value { |gem| text = text.gsub(gem.full_gem_path, "GEM_ROOT/#{gem.name}") }
    text.gsub(Rails.root.to_s, 'RAILS_ROOT')
        .gsub(RbConfig::CONFIG.fetch('prefix'), 'RUBY_ROOT')
        .gsub(%r{([\w./-]+):\d+(?=:in\b)}, '\1:LINE')
        .gsub(/(Extracted source \(around line <strong>)#\d+/, '\1#LINE')
        .gsub(%r{(<pre class="line_numbers">)(.*?)(</pre>)}m) do
          match = Regexp.last_match
          "#{match[1]}#{match[2].gsub(/>\d+</, '>LINE<')}#{match[3]}"
        end
  end
end
