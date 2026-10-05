# frozen_string_literal: true

require_relative 'fixture_recording'

module NormalImportFormatsSupport
  DIR = Rails.root.join('app-phoenix/test/fixtures/imports/formats')
  POINT_COLUMNS = %w[lonlat timestamp altitude altitude_decimal accuracy vertical_accuracy battery velocity ping
                     tracker_id ssid bssid topic battery_status connection trigger inrids in_regions motion_data
                     course course_accuracy raw_data].freeze
  IMPORT_COLUMNS = %w[source raw_points doubles processed raw_data status error_message].freeze

  class BatchWriter
    include Imports::BulkInsertable
    attr_reader :import

    def initialize(import, atomic)
      @import = import
      @atomic = atomic
    end

    def write(rows) = bulk_insert_points(rows)
    def atomic_bulk_insert? = @atomic
    def importer_name = 'CSV'
  end

  module_function

  def write(name, value)
    FixtureRecording.verify(DIR.join("#{name}.json"), "#{JSON.pretty_generate(value)}\n")
  end

  def capture_csv(zone)
    output = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      user, import = owner!(zone)
      input = "latitude,longitude,timestamp,altitude,tracker_id\n51.3,12.4,2026-01-15 23:30:00,12.75,oracle\n"
      FileUtils.mkdir_p(DIR)
      path = DIR.join('csv_valid.csv')
      FixtureRecording.verify(path, input)
      importer = Csv::Importer.new(import, user.id, path.to_s)
      2.times { importer.call }
      output = snapshot(import).merge('zone' => zone, 'locale' => 'en', 'input' => path.basename.to_s,
                                      'detector' => Imports::SourceDetector.new_from_file_header(path).detect_source.to_s,
                                      'error' => nil)
      raise ActiveRecord::Rollback
    end
    output
  end

  def owner!(zone, locale = 'en')
    connection = ActiveRecord::Base.connection
    settings = connection.quote({ 'timezone' => zone, 'locale' => locale }.to_json)
    connection.execute(<<~SQL)
      INSERT INTO users(id,email,settings,created_at,updated_at)
      VALUES (987001,'normal-formats@example.invalid',#{settings},'2026-01-15 23:30:00','2026-01-15 23:30:00')
    SQL
    connection.execute(<<~SQL)
      INSERT INTO imports(id,user_id,name,source,created_at,updated_at)
      VALUES (987101,987001,'oracle.csv',10,'2026-01-15 23:30:00','2026-01-15 23:30:00')
    SQL
    [User.find(987_001), Import.find(987_101)]
  end

  def capture_batch_failure(atomic)
    _, import = owner!('UTC', 'de')
    batches = [1000, 1].each_with_index.map do |size, batch|
      size.times.map do |i|
        { lonlat: 'POINT(12.4 51.3)', timestamp: Time.current.to_i + i + batch * 1000,
          altitude: 12, altitude_decimal: batch.zero? ? 12.75 : 100_000_000,
          raw_data: { 'flag' => false, 'nullable' => nil }, tracker_id: 'oracle',
          user_id: import.user_id, import_id: import.id, created_at: Time.current, updated_at: Time.current }
      end
    end
    input = 'batch_failure_input.json'
    write(input.delete_suffix('.json'), batches)
    writer = BatchWriter.new(import, atomic)
    failure = nil
    begin
      if atomic
        ActiveRecord::Base.transaction { batches.each { |batch| writer.write(batch) } }
      else
        batches.each { |batch| writer.write(batch) }
      end
    rescue ActiveRecord::StatementInvalid => e
      failure = { 'class' => e.class.name, 'message' => e.message }
    end
    snapshot(import).merge('zone' => 'UTC', 'locale' => 'de', 'input' => input, 'error' => failure)
  ensure
    connection = ActiveRecord::Base.connection
    %w[points notifications imports users].each do |table|
      key = table == 'users' ? 'id' : 'user_id'
      connection.execute("DELETE FROM #{table} WHERE #{key}=987001")
    end
  end

  def snapshot(import)
    connection = ActiveRecord::Base.connection
    sql = (POINT_COLUMNS & Point.column_names).map do |column|
      column == 'lonlat' ? 'ST_AsText(lonlat::geometry) AS lonlat' : connection.quote_column_name(column)
    end.join(',')
    points = connection.select_all("SELECT #{sql} FROM points WHERE import_id=#{import.id} ORDER BY id").to_a
    points.each do |point|
      %w[motion_data raw_data].each { |key| point[key] = JSON.parse(point[key]) if point[key].is_a?(String) }
      %w[inrids in_regions].each { |key| point[key] = Point.type_for_attribute(key).deserialize(point[key]) }
      %w[altitude_decimal course course_accuracy].each do |key|
        point[key] = point[key]&.to_s if point.key?(key)
      end
    end
    sources = if Point.column_names.include?('source_id')
                connection.select_all(<<~SQL).to_a
                  SELECT digest,tracker_id,topic,ssid,bssid,connection,trigger,battery_status,
                         array_to_json(inrids) AS inrids,array_to_json(in_regions) AS in_regions
                  FROM point_sources WHERE id IN (SELECT source_id FROM points WHERE import_id=#{import.id}) ORDER BY digest
                SQL
              else
                []
              end
    sources.each do |source|
      %w[inrids in_regions].each { |key| source[key] = JSON.parse(source[key]) if source[key].is_a?(String) }
    end
    { 'import' => import.reload.attributes.slice(*IMPORT_COLUMNS), 'points' => points, 'sources' => sources,
      'notifications' => Notification.where(user_id: import.user_id).order(:id).pluck(:title, :content, :kind),
      'jobs' => ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| { 'type' => job[:job].name, 'args' => job[:args] } } }
  end

  def capture_detection
    detection_cases.map do |name, bytes, expected|
      path = DIR.join("detection_#{name}")
      FixtureRecording.verify(path, bytes)
      { 'input' => path.basename.to_s, 'filename' => name, 'expected' => expected,
        'source' => Imports::SourceDetector.new_from_file_header(path).detect_source&.to_s }
    end
  end

  def detection_cases
    mobile = { type: 'DawarichPhotoLibrary', version: 1,
               points: [{ timestamp: 1, latitude: 51.3, longitude: 12.4 }] }
    [
      ['ambiguous.json', { locations: [{ latitudeE7: 513_000_000, longitudeE7: 124_000_000,
                                       lat: 51.3, lon: 12.4, time: 1 }] }.to_json, 'google_records'],
      ['mobile_v1.json', mobile.to_json, 'mobile_photo_library'],
      ['mobile_v2.json', mobile.merge(version: 2).to_json, nil],
      ['mobile_large_v1.json', "#{mobile.to_json.delete_suffix('}')},\"padding\":\"#{'x' * 9000}",
       'mobile_photo_library'],
      ['mobile_large_v2.json', "#{mobile.merge(version: 2).to_json.delete_suffix('}')},\"padding\":\"#{'x' * 9000}",
       nil],
      ['mobile_empty.json', mobile.merge(points: []).to_json, 'mobile_photo_library'],
      ['mobile_missing_type.json', { version: 1, points: mobile[:points] }.to_json, nil],
      ['empty.json', '', nil], ['null.json', 'null', nil], ['false.json', 'false', nil],
      ['partial.json', '{"locations":[{"latitudeE7":513000000}', 'google_records'],
      ['records_fallback.json', "{\"padding\":\"#{'x' * 9000}\",\"locations\":[{\"latitudeE7\":1", 'google_records'],
      ['outside_raw_limit.json', "#{'x' * 262_144}\"locations\" \"latitudeE7\"", nil],
      ['semantic.json', '{"timelineObjects":[{"placeVisit":{}}]}', 'google_semantic_history'],
      ['phone.json', '{"semanticSegments":[{"startTime":"2026-01-15"}]}', 'google_phone_takeout'],
      ['raw.json', '{"rawSignals":[]}', 'google_phone_takeout'],
      ['photos.json', '{"title":"a","creationTime":{"timestamp":"1"},"imageViews":0}', 'google_photos'],
      ['geo.json', '{"type":"FeatureCollection","features":[{"geometry":null}]}', 'geojson'],
      ['polar.json', '{"locations":[{"lat":51.3,"lon":12.4,"time":1}]}', 'polarsteps'],
      ['polar_comment.json', '/* root */{"locations":[{"lat":51.3,"lon":12.4,"time":1}]}', 'polarsteps'],
      ['segments.json', '[{"arrived":null,"departed":1}]', 'polarsteps'],
      ['track.rec', 'invalid', 'owntracks'],
      ['track.json', 'prefix {"_type":"location"}', 'owntracks'],
      ['track.gpx', "\xEF\xBB\xBF<gpx></gpx>", 'gpx'],
      ['late.gpx', "<?xml #{' ' * 1024}<gpx>", nil],
      ['track.kml', '<kml></kml>', 'kml'], ['track.kmz', 'PKanything', 'kml'],
      ['track.zip', [80, 75, 3, 4].pack('C*'), 'zip'],
      ['track.fit', '12345678.FIT', 'fit'],
      ['track.tcx', '<TrainingCenterDatabase>', 'tcx'],
      ['track.csv', "latitude;longitude;timestamp\n51.3;12.4;1", 'csv'],
      ['unrecognized.csv', 'foo,bar,baz', nil]
    ]
  end

  def capture_csv_lexical
    cases = [
      ['empty', '', ','], ['newline', "\n", ','], ['crlf', "\r\n", ','],
      ['trailing_nil', 'a,', ','], ['all_nil', ',,', ','], ['quoted_empty', '"",', ','],
      ['quotes', '"a,b","a""b"', ','], ['spaces', ' a,b ', ','], ['first_record', "a\nb", ','],
      ['bom', "\xEF\xBB\xBFa,b", ','], ['semicolon', 'a;"";', ';'], ['tab', "a\t\"\"\t", "\t"],
      ['quoted_newline', "\"a\nb\",c", ','], ['quoted_crlf', "\"a\r\nb\",c", ','],
      ['unclosed', '"a', ','], ['illegal', 'a"b,c', ','], ['after_quote', '"a"x,b', ','],
      ['after_quote_space', '"a" ,b', ',']
    ]
    records = cases.map do |name, line, delimiter|
      result = { 'name' => name, 'line' => line, 'delimiter' => delimiter, 'kind' => 'records' }
      begin
        result.merge('fields' => CSV.parse_line(line, col_sep: delimiter), 'error' => nil)
      rescue CSV::MalformedCSVError => e
        result.merge('error' => { 'class' => e.class.name, 'message' => e.message })
      end
    end
    records + csv_detector_cases.map do |name, bytes|
      path = DIR.join("csv_detector_#{name}.csv")
      FixtureRecording.verify(path, bytes)
      result = { 'name' => name, 'input' => path.basename.to_s, 'kind' => 'detector' }
      begin
        result.merge('detection' => Csv::Detector.new(path).call, 'error' => nil)
      rescue StandardError => e
        result.merge('error' => { 'class' => e.class.name, 'message' => e.message })
      end
    end
  end

  def csv_detector_cases
    [
      ['decimal', "latitude,longitude,timestamp,altitude\n51.3,12.4,1768519800,12.75\n"],
      ['semicolon', "latitude;longitude;timestamp\n51,3;12,4;1768519800000\n"],
      ['tab', "LATITUDE N/S\tLONGITUDE E/W\tdate\ttime\n51.3N\t12.4W\t2026-01-15\t23:30:00\n"],
      ['aliases', "latitude,lat,longitude,lon,date,time,timestamp\n11,513000000,22,124000000,x,y,1768519800\n"],
      ['bom', "\xEF\xBB\xBFlatitude,longitude,timestamp\n51.3,12.4,2026-01-15\n"],
      ['empty', ''], ['missing', "latitude,timestamp\n51.3,1\n"],
      ['quoted_newline', "latitude,longitude,timestamp\n\"51\n.3\",12.4,1\n"]
    ]
  end

  def csv_import_cases
    header = "latitude,longitude,timestamp,altitude,speed,accuracy,battery,heading,tracker_id\n"
    row = lambda { |index, altitude = '12.75'|
      "51.3,12.4,#{1_768_519_800 + index},#{altitude},1.25,2.9,88.7,42.12345,oracle\n"
    }
    cases = [
      ['csv_import_empty', '', 'UTC', false],
      ['csv_import_header', header, 'UTC', false],
      ['csv_import_skipped', "#{header},12.4,1768519800,,,,,,\n51.3,,1768519800,,,,,,\n#{row.call(0)}", 'UTC', false],
      ['csv_import_duplicate', header + row.call(0) * 1001, 'UTC', false],
      ['csv_import_bad_quote', "#{header}\"51.3,12.4,1768519800\n", 'UTC', false],
      ['csv_import_failure', header + 2001.times.map { |i| row.call(i, i == 1000 ? '100000000' : '12.75') }.join,
       'UTC', false],
      ['csv_import_legacy', header + row.call(0), 'UTC', true]
    ]
    [999, 1000, 1001, 2001].each do |count|
      cases << ["csv_import_#{count}", header + count.times.map { |i| row.call(i) }.join, 'UTC', false]
    end
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["csv_import_time_#{zone.tr('/', '_')}",
                "latitude,longitude,date,time,altitude\n51.3,12.4,2026-01-15,23:30:00,12.75\n", zone, false]
    end
    csv_detector_cases.first(5).each do |name, bytes|
      cases << ["csv_import_detection_#{name}", bytes, 'UTC', false]
    end
    cases
  end

  def capture_csv_case(name, bytes, zone, legacy)
    if legacy
      output = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute('ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal')
        Point.reset_column_information
        Points::DimensionResolver.reset_column_availability!
        output = capture_csv_case(name, bytes, zone, false).merge('legacy' => true)
        raise ActiveRecord::Rollback
      end
      return output
    end

    Time.use_zone(zone) do
      I18n.with_locale(:de) do
        user, import = owner!(zone, 'de')
        input = "#{name}.csv"
        path = DIR.join(input)
        FixtureRecording.verify(path, bytes)
        error = nil
        begin
          Csv::Importer.new(import, user.id, path.to_s).call
        rescue StandardError => e
          error = { 'class' => e.class.name, 'message' => e.message }
        end
        snapshot(import).merge('zone' => zone, 'locale' => 'de', 'input' => input, 'error' => error)
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

  def owntracks_cases
    point = { '_type' => 'location', 'lat' => 51.3, 'lon' => 12.4, 'tst' => 1_768_519_800,
              'alt' => 12.75, 'vel' => 36.0, 'topic' => 'owntracks/test', 'SSID' => 'synthetic',
              'BSSID' => 'synthetic', 'batt' => 88, 'acc' => 2, 'vac' => 3, 'bs' => 2, 'conn' => 'w',
              't' => 'p', 'm' => 0, 'tid' => 'oracle', 'inrids' => [], 'inregions' => nil }
    line = ->(attrs) { "2026-01-15T23:30:00Z\t*\t#{attrs.to_json}\n" }
    mixed = [point, point.merge('_type' => 'waypoint', 'tst' => point['tst'] + 1),
             point.merge('_type' => 'status', 'tst' => point['tst'] + 2),
             point.except('_type').merge('tst' => point['tst'] + 3), point.merge('lat' => nil)]
    flags = point.merge('m' => false, 'p' => false, 'batt' => false, 'vel' => false,
                        'topic' => nil, 'inrids' => nil, 'inregions' => [])
    cases = [
      ['owntracks_import_empty', ''], ['owntracks_import_valid', line.call(point)],
      ['owntracks_import_legacy', line.call(point)],
      ['owntracks_import_mixed', "#{mixed.map(&line).join}1\t*\t{broken\n1\t-\t{}\n"],
      ['owntracks_import_flags', line.call(flags)],
      ['owntracks_import_whitespace', "1 * #{point.to_json}\n"],
      ['owntracks_import_duplicate', line.call(point) * 1001],
      ['owntracks_import_invalid_utf8', line.call(point).sub('oracle', "oracle\xFF").b],
      ['owntracks_import_bad', "1\t*\t{broken\nmissing\n"],
      ['owntracks_import_failure', 2001.times.map do |i|
        line.call(point.merge('tst' => point['tst'] + i, 'alt' => i == 1000 ? 100_000_000 : 12.75))
      end.join]
    ]
    [999, 1000, 1001, 2001].each do |count|
      bytes = count.times.map { |i| line.call(point.merge('tst' => point['tst'] + i)) }.join
      cases << ["owntracks_import_#{count}", bytes]
    end
    cases
  end

  def geojson_cases
    feature = { type: 'Feature', geometry: { type: 'Point', coordinates: [12.4, 51.3, 12.75] },
                properties: { timestamp: 1_768_519_800, battery: 0.72, speed_kmh: 36, tracker_id: 'oracle',
                              accuracy: 2, vertical_accuracy: 3, heading: 90.5, wifi: 'synthetic',
                              battery_state: 'charging', motion: ['walking'], activity: false } }
    collection = ->(features) { { type: 'FeatureCollection', features: features }.to_json }
    cases = [
      ['geojson_import_empty', '', 'UTC'], ['geojson_import_valid', feature.to_json, 'UTC'],
      ['geojson_import_legacy', feature.to_json, 'UTC'],
      ['geojson_import_duplicate', collection.call([feature] * 1001), 'UTC'],
      ['geojson_import_milliseconds', feature.merge(properties: { timestamp: 1_768_519_800_123 }).to_json, 'UTC'],
      ['geojson_import_alias_order', feature.merge(properties: { vel: 3, speed: 99, tst: 1_768_519_800,
                                                               timestamp: 1, BATTERY: 0.72 }).to_json, 'UTC'],
      ['geojson_import_invalid_utf8', feature.to_json.sub('oracle', "oracle\xFF").b, 'UTC'],
      ['geojson_import_timeless', collection.call([feature, feature.merge(properties: {})]), 'UTC'],
      ['geojson_import_comment', "/* root */#{feature.to_json}", 'UTC'],
      ['geojson_import_line', { type: 'Feature', geometry: { type: 'LineString', coordinates:
        [[12.4, 51.3, 0, 1_768_519_800], [12.5, 51.4, 0, '2026-01-15T23:31:00Z'], [12.6, 51.5]] } }.to_json, 'UTC'],
      ['geojson_import_multi', { type: 'Feature', geometry: { type: 'MultiLineString', coordinates:
        [[[12.4, 51.3, 0, 1_768_519_800]], [[12.5, 51.4, 0, 1_768_519_801]]] } }.to_json, 'UTC'],
      ['geojson_import_invalid_geometry', collection.call([feature.merge(geometry: nil)]), 'UTC']
    ]
    [999, 1000, 1001, 2001].each do |count|
      features = count.times.map do |i|
        feature.merge(properties: feature[:properties].merge(timestamp: 1_768_519_800 + i))
      end
      cases << ["geojson_import_#{count}", collection.call(features), 'UTC']
    end
    features = 1001.times.map do |i|
      properties = feature[:properties].merge(timestamp: 1_768_519_800 + i)
      properties[:altitude] = 100_000_000 if i == 1000
      feature.merge(properties: properties)
    end
    cases << ['geojson_import_failure', collection.call(features), 'UTC']
    cases << ['geojson_import_malformed', collection.call(features).delete_suffix(']}'), 'UTC']
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      properties = { recorded_at: '2026-01-15 23:30:00', vel: '3.25', batt: -1, deviceId: 'alias' }
      dated = feature.merge(properties: properties)
      cases << ["geojson_import_#{zone.tr('/', '_')}", dated.to_json, zone]
    end
    cases
  end

  def capture_geojson(name, bytes, zone, legacy = name.end_with?('_legacy'))
    if legacy
      output = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute('ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal')
        Point.reset_column_information
        Points::DimensionResolver.reset_column_availability!
        output = capture_geojson(name, bytes, zone, false).merge('legacy' => true)
        raise ActiveRecord::Rollback
      end
      return output
    end
    Time.use_zone(zone) do
      I18n.with_locale(:de) do
        user, import = owner!(zone, 'de')
        import.update_columns(source: 6, name: "#{name}.geojson")
        input = "#{name}.geojson"
        path = DIR.join(input)
        FixtureRecording.verify(path, bytes)
        error = nil
        begin
          Geojson::Importer.new(import, user.id, path.to_s).call
        rescue StandardError => e
          error = { 'class' => e.class.name, 'message' => e.message }
        end
        snapshot(import).merge('zone' => zone, 'locale' => 'de', 'input' => input, 'error' => error)
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

  def capture_owntracks(name, bytes, legacy = name.end_with?('_legacy'))
    if legacy
      output = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute('ALTER TABLE points DROP COLUMN source_id, DROP COLUMN altitude_decimal')
        Point.reset_column_information
        Points::DimensionResolver.reset_column_availability!
        output = capture_owntracks(name, bytes, false).merge('legacy' => true)
        raise ActiveRecord::Rollback
      end
      return output
    end
    Time.use_zone('UTC') do
      I18n.with_locale(:de) do
        user, import = owner!('UTC', 'de')
        import.update_columns(source: 1, name: "#{name}.rec")
        input = "#{name}.rec"
        path = DIR.join(input)
        FixtureRecording.verify(path, bytes)
        error = nil
        begin
          OwnTracks::Importer.new(import, user.id, path.to_s).call
        rescue StandardError => e
          error = { 'class' => e.class.name, 'message' => e.message }
        end
        snapshot(import).merge('zone' => 'UTC', 'locale' => 'de', 'input' => input, 'error' => error)
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
end
