# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def google_semantic_cases
    duration = { startTimestamp: '2026-01-15T23:30:00Z', endTimestamp: '2026-01-15T23:40:00Z' }
    location = { latitudeE7: 513_000_000, longitudeE7: 124_000_000, accuracyMetres: 2 }
    visit = { placeVisit: { location: location, duration: duration } }
    activity = { activitySegment: { startLocation: location, endLocation: location.merge(latitudeE7: 514_000_000),
                                   duration: duration, activityType: 'WALKING', activities: [],
                                   simplifiedRawPath: { points: [location] } } }
    waypoint = { activitySegment: { duration: duration, startLocation: {},
                                   waypointPath: { travelMode: 'WALK', waypoints: [
                                     { latE7: 513_000_001, lngE7: 124_000_001 },
                                     { latE7: 514_000_000, lngE7: 125_000_000 }
                                   ] } } }
    mixed = [visit, activity, waypoint, { placeVisit: { location: {}, otherCandidateLocations: [location],
                                                     duration: duration } }, {},
             { placeVisit: { location: { latitudeE7: 0, longitudeE7: 0 }, duration: duration } }]
    collection = ->(points) { { timelineObjects: points }.to_json }
    cases = [['semantic_import_empty', '', 'UTC'], ['semantic_import_valid', collection.call(mixed), 'UTC'],
             ['semantic_import_none', collection.call([]), 'UTC'], ['semantic_import_missing', '{}', 'UTC'],
             ['semantic_import_null', 'null', 'UTC'],
             ['semantic_import_nil_point', collection.call([visit, nil]), 'UTC'],
             ['semantic_import_legacy', collection.call([visit]), 'UTC'],
             ['semantic_import_duplicate', collection.call([visit] * 1001), 'UTC'],
             ['semantic_import_end_only', collection.call([{ activitySegment: { endLocation: location,
                                                                              duration: duration } }]), 'UTC'],
             ['semantic_import_bad_coordinates',
              collection.call([{ placeVisit: { location: location.merge(latitudeE7: true),
                                                                                  duration: duration } }]), 'UTC']]
    [999, 1000, 1001, 2001].each do |count|
      cases << ["semantic_import_#{count}", collection.call(count.times.map do |i|
        { placeVisit: { location: location, duration: { startTimestampMs: (1_768_519_800_000 + i * 1000).to_s } } }
      end), 'UTC']
    end
    cases << ['semantic_import_failure', collection.call(2001.times.map do |i|
      { placeVisit: { location: location.merge(accuracyMetres: i == 1000 ? 2_147_483_648 : 2),
                      duration: { startTimestampMs: (1_768_519_800_000 + i * 1000).to_s } } }
    end), 'UTC']
    cases << ['semantic_import_malformed', cases.last[1].delete_suffix(']}'), 'UTC']
    cases << ['semantic_import_late_preparation', collection.call([visit] * 1000 + [nil]), 'UTC']
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      dated = { placeVisit: { location: location, duration: { startTimestamp: -1 } } }
      cases << ["semantic_import_time_#{zone.tr('/', '_')}", collection.call([dated]), zone]
    end
    cases
  end
end
