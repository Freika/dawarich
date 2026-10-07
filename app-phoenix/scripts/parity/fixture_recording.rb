# frozen_string_literal: true

module FixtureRecording
  SECRET = 'phoenix-a2-cookie-fixture-secret-not-for-production'

  def self.canonical_timezone_latitudes
    source = TZInfo::DataSources::RubyDataSource.new
    source.country_codes.each_with_object({}) do |code, latitudes|
      source.get_country_info(code).zones.each do |zone|
        latitudes[zone.identifier] ||= zone.latitude.to_f
      end
    end.freeze
  end

  module SyntheticSecret
    def self.included(base)
      base.before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return(SECRET)
        random = Random.new(1153)
        allow(SecureRandom).to receive(:random_bytes) { |n| random.bytes(n || 16) }
        allow(OpenSSL::Random).to receive(:random_bytes) { |n| random.bytes(n) }
        allow_any_instance_of(OpenSSL::Cipher).to receive(:random_iv) do |cipher|
          cipher.iv = random.bytes(cipher.iv_len)
        end
        allow(Rack::Utils).to receive(:clock_time).and_return(0.0)
      end
      base.around do |example|
        app = Rails.application
        previous = app.config.secret_key_base
        env = app.env_config.slice('action_dispatch.secret_key_base', 'action_dispatch.key_generator')
        turbo_key = Turbo.signed_stream_verifier_key
        storage_verifier = ActiveStorage.verifier
        global_id_verifier = SignedGlobalID.verifier
        configured_global_id_verifier = app.config.global_id.verifier
        caches = [[app, :@message_verifiers], [ActiveStorage::Blob, :@signed_id_verifier],
                  [Turbo::StreamsChannel, :@signed_stream_verifier]].map do |owner, key|
          [owner, key, owner.instance_variable_defined?(key), owner.instance_variable_get(key)]
        end
        app.config.secret_key_base = SECRET
        app.env_config.merge!('action_dispatch.secret_key_base' => SECRET,
                              'action_dispatch.key_generator' => app.key_generator)
        Turbo.signed_stream_verifier_key = app.key_generator.generate_key('turbo/signed_stream_verifier_key')
        caches.each { |owner, key, _present, _value| owner.instance_variable_set(key, nil) }
        ActiveStorage.verifier = app.message_verifier('ActiveStorage')
        SignedGlobalID.verifier = GlobalID::Verifier.new(app.key_generator.generate_key('signed_global_ids'))
        app.config.global_id.verifier = SignedGlobalID.verifier
        example.run
      ensure
        app.config.secret_key_base = previous
        app.env_config.merge!(env)
        Turbo.signed_stream_verifier_key = turbo_key
        ActiveStorage.verifier = storage_verifier
        SignedGlobalID.verifier = global_id_verifier
        app.config.global_id.verifier = configured_global_id_verifier
        caches.each do |owner, key, present, value|
          if present
            owner.instance_variable_set(key, value)
          elsif owner.instance_variable_defined?(key)
            owner.remove_instance_variable(key)
          end
        end
      end
    end
  end

  module CanonicalTimezone
    def self.included(base)
      base.before(:context) { @fixture_recording_context_timezone = ENV.delete('TIME_ZONE') }
      base.after(:context) do
        value = @fixture_recording_context_timezone
        value.nil? ? ENV.delete('TIME_ZONE') : ENV['TIME_ZONE'] = value
      end
      base.around do |example|
        previous = ENV.fetch('TIME_ZONE', nil)
        ENV.delete('TIME_ZONE')
        Time.use_zone('Europe/Berlin') { example.run }
      ensure
        previous.nil? ? ENV.delete('TIME_ZONE') : ENV['TIME_ZONE'] = previous
      end
      base.before do |example|
        defaults = Users::SafeSettings::DEFAULT_VALUES.merge('timezone' => example.metadata.fetch(:fixture_timezone,
                                                                                                  'UTC'))
        stub_const('Users::SafeSettings::DEFAULT_VALUES', defaults.freeze)
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

  def self.source_verify(path, bytes)
    root = File.expand_path(path).sub('/test/fixtures/', '/test/fixtures/a12f3a_source/')
    verify(root, "#{JSON.generate(JSON.parse(bytes))}\n")
  end

  def self.verify(path, bytes, json_bodies: [])
    bytes = normalize(bytes)
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    else
      expected = File.binread(path)
      equal = if json_bodies.empty?
                expected == bytes.b
              else
                json_with_bodies(expected, json_bodies) == json_with_bodies(bytes, json_bodies)
              end
      raise "#{path} differs from Rails" unless equal
    end
  end

  def self.json_with_bodies(bytes, paths)
    value = JSON.parse(bytes)
    paths.each do |path|
      parent = value.dig(*path[0...-1])
      parent[path.last] = JSON.parse(parent.fetch(path.last))
    end
    value
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
        .gsub(%r{(?<=[\w./-]):\d+(?=:in\b)}, ':LINE')
        .gsub(%r{(/auth/dawarich\?token=)eyJ[\w-]+\.[\w-]+\.[\w-]+}, '\1JWT')
        .gsub(/(data-exception-object-id=\\?"|onclick=\\?"return toggle\(|<div id=\\?")\d+/, '\1OBJECT')
        .gsub(/(Extracted source \(around line <strong>)#\d+/, '\1#LINE')
        .gsub(%r{(<pre class="line_numbers">)(.*?)(</pre>)}m) do
          match = Regexp.last_match
          "#{match[1]}#{match[2].gsub(/>\d+</, '>LINE<')}#{match[3]}"
        end
  end
end
