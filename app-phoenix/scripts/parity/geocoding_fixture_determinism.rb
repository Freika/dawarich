# frozen_string_literal: true

# Only this oracle installs the callbacks/context. IDs enter actual persistence
# inputs, including bulk siblings, so effects and keys use recorded identities.
module GeocodingFixtureDeterminism
  FIRST_ID = 1_000_001
  TABLES = %w[users points places countries instance_settings].freeze
  FIXTURES = %w[photon_komoot photon_selfhosted_key photon_chibigeo geoapify nominatim locationiq
                store_geodata_false country_alias_and_mismatch point_force_and_rerun point_batch
                point_job_disabled place_siblings place_name_locked place_privacy_mode place_name_too_long
                place_without_coordinates place_lonlat_from_decimals config_resolution search_outcomes].freeze
  ID_RANGES = FIXTURES.each_with_index.to_h do |name, index|
    first = FIRST_ID + ((index + 1) * 1000)
    ranges = TABLES.index_with { first..(first + 999) }
    # These identities are also concrete worker/DB-error-hook consumer inputs.
    ranges['points'] = 6207..6211 if name == 'point_batch'
    ranges['countries'] = 35..35 if name == 'country_alias_and_mismatch'
    [name, ranges.freeze]
  end.freeze

  class FixtureCipher < ActiveRecord::Encryption::Cipher
    def encrypt(clean_text, key:, **options)
      super(clean_text, key:, **options.merge(deterministic: true))
    end
  end

  module Oracle
    def self.included(base)
      base.around do |example|
        GeocodingFixtureDeterminism.with(scope: example.metadata.fetch(:fixture)) do |allocate_id|
          @fixture_allocate_id = allocate_id
          example.run
        end
      end
      base.before do
        # New siblings bypass validations; preserve the real bulk SQL operation.
        allow(Place).to receive(:insert_all).and_wrap_original do |original, attributes, **options|
          rows = attributes.map { |row| row.merge(id: @fixture_allocate_id.call(Place)) }
          original.call(rows, **options)
        end
      end
    end

    def write_fixture(dir, name, data)
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        super
      else
        path = Rails.root.join("app-phoenix/test/fixtures/#{dir}/#{name}.json")
        bytes = "#{JSON.pretty_generate(data.merge('postgis_build' => postgis_build))}\n"
        expect(File.binread(path) == bytes).to be(true), "geocoding fixture #{name} raw bytes changed"
      end
    end
  end

  def self.validate_ranges!
    TABLES.each do |table|
      ID_RANGES.values.map { |ranges| ranges.fetch(table) }.sort_by(&:begin).each_cons(2) do |left, right|
        raise "overlapping geocoding fixture ranges in #{table}" if left.end >= right.begin
      end
    end
  end

  def self.with(scope: nil, &block)
    validate_ranges!
    ranges = scope ? ID_RANGES.fetch(scope.to_s) : TABLES.index_with { FIRST_ID..(FIRST_ID + 999) }
    models = [User, Point, Place, Country, InstanceSetting]
    installed = []
    counters = ranges.transform_values { |range| range.begin - 1 }
    thread = Thread.current
    allocate_id = lambda do |model|
      table = model.table_name
      id = counters[table] = counters.fetch(table) + 1
      raise "geocoding fixture ID range exhausted in #{table}" unless ranges.fetch(table).cover?(id)
      raise "geocoding fixture ID collision in #{table}" if model.unscoped.exists?(id:)

      id
    end
    pin_id = lambda do |record|
      record.id = allocate_id.call(record.class) if Thread.current.equal?(thread) && record.id.nil?
    end

    models.each do |model|
      model.before_validation(pin_id, on: :create, prepend: true)
      installed << model
    end
    # Retain supplied key/providers, real AES-GCM serialization and decryption.
    # Only the fixture IV is deterministic; production policy remains unchanged.
    ActiveRecord::Encryption.with_encryption_context(cipher: FixtureCipher.new) { block.call(allocate_id) }
  ensure
    installed&.reverse_each { |model| model.skip_callback(:validation, :before, pin_id) }
  end
end
