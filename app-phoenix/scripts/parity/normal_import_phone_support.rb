# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def google_phone_point_cases
    start_time = '2026-01-15T23:30:00Z'
    finish = '2026-01-15T23:40:00Z'
    metadata = { accuracyMeters: '2.9m', altitudeMeters: '12.755', speedMetersPerSecond: '3.25',
                 activityRecord: { probableActivities: [{ type: 'WALKING', confidence: 90 }] } }
    visit = metadata.merge(startTime: start_time,
                           visit: { topCandidate: { placeLocation: { latLng: 'geo:51.3°, 12.4°, 10.755' } } })
    activity = metadata.merge(startTime: start_time, endTime: finish,
                              activity: { start: { latLng: 'geo:51.3,12.4' }, end: { latLng: '51.4,12.5,0' },
                                          topCandidate: { type: 'WALKING' } })
    path = metadata.merge(timelinePath: [{ point: '51.3,12.4', time: start_time },
                                         { point: '51.4,12.5,1.25', time: finish }])
    raw_visit = visit.deep_dup
    raw_visit[:visit][:topCandidate][:placeLocation] = 'geo:51.3°,12.4°,10.755'
    raw_activity = activity.merge(activity: { start: '51.3,12.4', end: '51.4,12.5,0' })
    raw_path = metadata.merge(startTime: start_time, timelinePath: [
                                { point: '51.3,12.4', durationMinutesOffsetFromStartTime: '2.9' },
                                { point: '51.4,12.5', durationMinutesOffsetFromStartTime: -1 },
                                { point: '51.5,12.6', durationMinutesOffsetFromStartTime: nil }
                              ])
    position = metadata.merge(LatLng: 'geo:51.3,12.4', timestamp: start_time)
    cases = [['phone_points_semantic', :semantic_segment, [visit, activity, path, {}, { visit: {} }]],
             ['phone_points_array', :raw_array, [raw_visit, raw_activity, raw_path, {}]],
             ['phone_points_signal', :raw_signal, [{ position: position }, {}, { position: nil }]],
             ['phone_points_legacy', :semantic_segment, [visit, activity]],
             ['phone_points_missing_path_start', :raw_array, [raw_path.except(:startTime)]],
             ['phone_points_bad_time', :semantic_segment, [visit.merge(startTime: 'bad')]],
             ['phone_points_false_visit', :semantic_segment, [{ visit: false }]],
             ['phone_points_nil_path', :semantic_segment, [{ timelinePath: nil }]],
             ['phone_points_false_record', :raw_signal, [{ position: position.merge(activityRecord: false) }]],
             ['phone_points_nil_record', :raw_signal, [{ position: position.merge(activityRecord: nil) }]]]
    [nil, false, true, '', '0', '99.5m', 2_147_483_648, {}, [], 99_999_999.995,
     -100_000_000].each_with_index do |value, i|
      typed = position.merge(accuracyMeters: value, altitudeMeters: value, speedMetersPerSecond: value,
                             activity: value, activityRecord: { probableActivities: value })
      cases << ["phone_points_metadata_#{i}", :raw_signal, [{ position: typed }]]
    end
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["phone_points_time_#{zone.tr('/', '_')}", :semantic_segment, [visit, activity], zone]
    end
    cases.map { |name, section, value, zone| [name, section, value, zone || 'UTC', name.end_with?('_legacy')] }
  end

  def capture_phone_preparation(section, value, zone, legacy)
    import = Import.new(id: 987_101, user_id: 987_001)
    attrs = []
    error = nil
    Time.use_zone(zone) do
      importer = GoogleMaps::PhoneTakeoutImporter.new(import, import.user_id)
      importer.send(:initialize_stream)
      input = JSON.parse(JSON.generate(value))
      method = { semantic_segment: :parse_semantic_segments, raw_signal: :parse_raw_signals,
                 raw_array: :parse_raw_array }.fetch(section)
      attrs = Array(importer.send(method, input)).flatten.compact.map do |point|
        point.merge(importer.send(:point_metadata)).stringify_keys
      end
    rescue StandardError => e
      error = { 'class' => e.class.name, 'message' => e.message }
    end
    { 'section' => section.to_s, 'input' => value, 'zone' => zone, 'legacy' => legacy,
      'prepared_points' => JSON.parse(JSON.generate(attrs)), 'error' => error,
      'identities' => { 'user_id' => import.user_id, 'import_id' => import.id } }
  end
end
