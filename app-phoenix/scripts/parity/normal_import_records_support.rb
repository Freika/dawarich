# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def google_records_cases
    location = { latitudeE7: 513_000_000, longitudeE7: 124_000_000, timestamp: '1768519800', altitude: 12.75,
                 velocity: 3.25, accuracy: 2, verticalAccuracy: 3, heading: 90.5, batteryCharging: false,
                 deviceTag: 42,
                 activity: [{ timestamp: '1768519801', activity: [{ type: 'WALKING', confidence: 90 }] }] }
    collection = ->(points) { { locations: points }.to_json }
    variants = [location, location.merge(deviceTag: nil, timestamp: '2026-01-15T23:30:00Z'),
                location.merge(deviceTag: false, timestamp: 'bad', batteryCharging: true),
                location.merge(deviceTag: ' ', timestamp: nil, timestampMs: '1768519800000'),
                location.merge(deviceTag: 'second', activity: false, activityRecord: { probableActivities: [] },
                               timestamp: -1, batteryCharging: nil),
                location.merge(deviceTag: 0, activity: [], timestamp: '1768519800000', batteryCharging: 0)]
    cases = [['records_import_empty', '', 'UTC'], ['records_import_valid', collection.call(variants), 'UTC'],
             ['records_import_legacy', collection.call([location]), 'UTC'],
             ['records_import_none', '{"locations":[]}', 'UTC'], ['records_import_wrong', '[]', 'UTC'],
             ['records_import_null', 'null', 'UTC'],
             ['records_import_duplicate', collection.call([location] * 1001), 'UTC'],
             ['records_import_late',
              "#{collection.call(variants).delete_suffix('}')},\"devices\":[{\"deviceTag\":42}]}",
              'UTC'],
             ['records_import_nil_point', collection.call([location, nil]), 'UTC'],
             ['records_import_bad_coordinates', collection.call([location.merge(latitudeE7: false)]), 'UTC']]
    [999, 1000, 1001, 2001].each do |count|
      cases << ["records_import_#{count}", collection.call(count.times.map do |i|
        location.merge(timestamp: (1_768_519_800 + i).to_s)
      end), 'UTC']
    end
    cases << ['records_import_failure', collection.call(2001.times.map do |i|
      location.merge(timestamp: (1_768_519_800 + i).to_s, altitude: i == 1000 ? 100_000_000 : 12.75)
    end), 'UTC']
    cases << ['records_import_malformed', cases.last[1].delete_suffix(']}'), 'UTC']
    cases << ['records_import_late_preparation', collection.call(1000.times.map do |i|
      location.merge(timestamp: (1_768_519_800 + i).to_s)
    end + [nil]), 'UTC']
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["records_import_time_#{zone.tr('/', '_')}", collection.call(variants), zone]
    end
    cases
  end

  def capture_records_preparation(bytes, zone)
    import = Import.new(id: 987_101, user_id: 987_001)
    attrs = []
    failure = nil
    Time.use_zone(zone) do
      payload = Oj.load(bytes.dup.force_encoding(Encoding::UTF_8).scrub, mode: :compat)
      locations = payload.is_a?(Hash) && payload['locations'].is_a?(Array) ? payload['locations'] : []
      importer = GoogleMaps::RecordsImporter.new(import)
      attrs = locations.map { |location| importer.send(:prepare_location_data, location).stringify_keys }
    rescue StandardError => e
      failure = { 'class' => e.class.name, 'message' => e.message }
    end
    tags = []
    begin
      handler = GoogleMaps::RecordsDeviceTagStreamHandler.new { |*args| tags << args }
      Oj.saj_parse(handler, bytes.dup.force_encoding(Encoding::UTF_8).scrub)
    rescue StandardError
      tags = []
    end
    { 'prepared_points' => JSON.parse(JSON.generate(attrs)), 'preparation_error' => failure,
      'device_tags' => tags, 'identities' => { 'user_id' => 987_001, 'import_id' => 987_101 } }
  end
end
