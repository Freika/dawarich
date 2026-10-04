# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def polarsteps_cases
    point = { lat: 51.3, lon: 12.4, time: '1768519800.75' }
    collection = ->(points) { { locations: points }.to_json }
    mixed = [point.merge(location: { lat: 51.4, lng: 12.5 }, lat: 1, lon: 2),
             point.merge(time: nil, timestamp: '2026-01-15 23:30:00'),
             point.except(:time).merge(arrived: nil, departed: '1768519802'),
             point.except(:time).merge(start_time: '1768519803'),
             point.except(:time).merge(end_time: '1768519804'),
             nil, false, [], point.merge(lat: nil), point.merge(time: 'bad'),
             point.merge(time: false, timestamp: '1768519805')]
    cases = [
      ['polarsteps_import_empty', '', 'UTC'], ['polarsteps_import_object', collection.call(mixed), 'UTC'],
      ['polarsteps_import_array', mixed.to_json, 'UTC'], ['polarsteps_import_wrong', '{"locations":{}}', 'UTC'],
      ['polarsteps_import_none', '[null,false,{}]', 'UTC'],
      ['polarsteps_import_duplicate', collection.call([point] * 1001), 'UTC'],
      ['polarsteps_import_legacy', collection.call([point]), 'UTC'],
      ['polarsteps_import_comment', "/* root */#{collection.call([point])}", 'UTC'],
      ['polarsteps_import_failure', collection.call(2001.times.map do |i|
        point.merge(time: i == 1000 ? 2_147_483_648 : 1_768_519_800 + i)
      end), 'UTC']
    ]
    [999, 1000, 1001, 2001].each do |count|
      bytes = collection.call(count.times.map { |i| point.merge(time: 1_768_519_800 + i) })
      cases << ["polarsteps_import_#{count}", bytes, 'UTC']
    end
    cases << ['polarsteps_import_malformed', cases.last[1].delete_suffix(']}'), 'UTC']
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["polarsteps_import_time_#{zone.tr('/', '_')}",
                collection.call([point.merge(time: '2026-01-15 23:30:00')]), zone]
    end
    cases
  end

  def mobile_photo_library_cases
    point = { latitude: 51.3, longitude: 12.4, timestamp: 1_768_519_800, altitude: 12.75 }
    envelope = { type: 'DawarichPhotoLibrary', version: 1, points: [point] }
    encode = ->(value) { JSON.generate(value, allow_nan: true) }
    collection = ->(points) { encode.call(envelope.merge(points: points)) }
    boundaries = [point.merge(latitude: -90, longitude: -180, timestamp: 2_147_483_647, altitude: 99_999_999.99),
                  point.merge(latitude: 90, longitude: 180, timestamp: 1, altitude: -99_999_999.99),
                  point.merge(timestamp: 2_147_483_648), point.merge(timestamp: 1_768_519_800_123),
                  point.merge(timestamp: 0.5), point.merge(altitude: 100_000_000, timestamp: 2),
                  point.merge(altitude: -100_000_000, timestamp: 3),
                  point.merge(latitude: 90.1), point.merge(longitude: -180.1),
                  point.merge(latitude: 0, longitude: 0), point.merge(timestamp: -1),
                  point.merge(timestamp: '2026-01-15'), point.merge(latitude: Float::INFINITY),
                  point.merge(longitude: Float::NAN), point.merge(altitude: Float::INFINITY, timestamp: 4),
                  point.merge(latitude: false), point.merge(timestamp: nil), nil, false, [],
                  point.merge(latitude: '51.3', longitude: '12.4', timestamp: '1768519801', altitude: '12.75')]
    cases = [['mobile_import_empty', '', 'UTC'], ['mobile_import_valid', encode.call(envelope), 'UTC'],
             ['mobile_import_boundaries', collection.call(boundaries), 'UTC'],
             ['mobile_import_legacy', encode.call(envelope), 'UTC'],
             ['mobile_import_version', encode.call(envelope.merge(version: 2)), 'UTC'],
             ['mobile_import_wrong_type', encode.call(envelope.merge(type: 'other')), 'UTC'],
             ['mobile_import_wrong_points', encode.call(envelope.merge(points: {})), 'UTC'],
             ['mobile_import_missing_points', encode.call(envelope.except(:points)), 'UTC'],
             ['mobile_import_array', encode.call([point]), 'UTC'],
             ['mobile_import_null', 'null', 'UTC'], ['mobile_import_none', collection.call([]), 'UTC'],
             ['mobile_import_duplicate', collection.call([point] * 1001), 'UTC'],
             ['mobile_import_rejected', collection.call([nil] * 1001), 'UTC'],
             ['mobile_import_second_rejected', collection.call(1000.times.map do |i|
               point.merge(timestamp: point[:timestamp] + i)
             end + [point.merge(timestamp: 2_147_483_648)]), 'UTC']]
    [999, 1000, 1001, 2001].each do |count|
      cases << ["mobile_import_#{count}", collection.call(count.times.map do |i|
        point.merge(timestamp: point[:timestamp] + i)
      end), 'UTC']
    end
    cases << ['mobile_import_malformed', cases.last[1].delete_suffix(']}'), 'UTC']
    cases
  end

  def capture_json(name, bytes, zone, source, importer, legacy = name.end_with?('_legacy'))
    if legacy
      output = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute('ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal')
        Point.reset_column_information
        Points::DimensionResolver.reset_column_availability!
        output = capture_json(name, bytes, zone, source, importer, false).merge('legacy' => true)
        raise ActiveRecord::Rollback
      end
      return output
    end
    Time.use_zone(zone) do
      I18n.with_locale(:de) do
        user, import = owner!(zone, 'de')
        import.update_columns(source: source, name: "#{name}.input.json")
        path = DIR.join("#{name}.input.json")
        File.binwrite(path, bytes)
        effects = []
        allow_json_effects(effects)
        error = nil
        begin
          repeats = source == 14 && name.end_with?('_duplicate') ? 2 : 1
          repeats.times { importer.new(import, user.id, path.to_s).call }
        rescue StandardError => e
          error = { 'class' => e.class.name, 'message' => e.message }
        end
        snapshot(import).merge('zone' => zone, 'locale' => 'de', 'input' => path.basename.to_s,
                               'error' => error, 'commands' => effects)
      end
    end
  ensure
    connection = ActiveRecord::Base.connection
    %w[points notifications imports users].each do |table|
      key = table == 'users' ? 'id' : 'user_id'
      connection.execute("DELETE FROM #{table} WHERE #{key}=987001")
    end
    Point.reset_column_information
    Points::DimensionResolver.reset_column_availability!
  end

  def allow_json_effects(effects)
    mocks = RSpec::Mocks::ExampleMethods
    observer = Object.new.extend(mocks)
    observer.allow(Points::TileEpoch).to observer.receive(:bump).and_wrap_original do |method, user_id, timestamps:|
      effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
      method.call(user_id, timestamps:)
    end
    observer.allow(Turbo::StreamsChannel).to observer.receive(:broadcast_replace_to).and_wrap_original do |m, *a, **o|
      if o[:partial] == 'imports/table_row'
        effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
      end
      m.call(*a, **o)
    end
  end
end
