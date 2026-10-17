# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def photos_cases
    google_photos_cases + generated_photos_cases
  end

  def google_photos_cases
    point = { geoDataExif: { latitude: 51.3, longitude: 12.4, altitude: 12.75 },
              geoData: { latitude: 51.4, longitude: 12.5, altitude: 0 },
              photoTakenTime: { timestamp: '1768519800123' }, creationTime: { timestamp: '1768519801' } }
    cases = [['google_photos_import_empty', ''], ['google_photos_import_valid', point.to_json],
             ['google_photos_import_duplicate', point.to_json],
             ['google_photos_import_legacy', point.to_json], ['google_photos_import_null', 'null'],
             ['google_photos_import_none', '{}'], ['google_photos_import_array', '[{}]'],
             ['google_photos_import_malformed', point.to_json.delete_suffix('}')],
             ['google_photos_import_fallback', point.merge(geoDataExif: {}, photoTakenTime: { timestamp: -1 }).to_json],
             ['google_photos_import_zero',
              point.merge(geoDataExif: { latitude: 0, longitude: 0 }, geoData: {}).to_json],
             ['google_photos_import_bad_time',
              point.merge(photoTakenTime: { timestamp: false }, creationTime: {}).to_json],
             ['google_photos_import_failure', point.merge(photoTakenTime: { timestamp: 2_147_483_648 }).to_json],
             ['google_photos_import_altitude',
              point.merge(geoDataExif: point[:geoDataExif].merge(altitude: 100_000_000)).to_json],
             ['google_photos_import_dig', point.merge(photoTakenTime: 1).to_json],
             ['google_photos_import_nonfinite', JSON.generate(point.merge(geoDataExif: { latitude: Float::INFINITY,
                                                                                       longitude: 12.4 }),
                                                              allow_nan: true)],
             ['google_photos_import_strings', point.merge(geoDataExif: { latitude: '51.3', longitude: '12.4',
                                                                       altitude: '12.75' }).to_json]]
    cases.map { |name, bytes| [name, bytes, 14] }
  end

  def generated_photos_cases
    point = { latitude: 51.3, longitude: 12.4, lonlat: 'POINT(12.5 51.4)', timestamp: '1768519800.75' }
    cases = []
    [5, 7].each do |source|
      prefix = source == 5 ? 'immich' : 'photoprism'
      mixed = [point, point.merge(timestamp: 'bad'), point.merge(latitude: 0, longitude: 0, timestamp: 2),
               point.merge(timestamp: 3, lonlat: 'POINT(0 0)'), point.merge(latitude: nil),
               point.merge(longitude: false), point.merge(timestamp: ''), point.merge(timestamp: 4, latitude: [])]
      cases += [["photos_#{prefix}_empty", '', source], ["photos_#{prefix}_valid", mixed.to_json, source],
                ["photos_#{prefix}_none", '[]', source],
                ["photos_#{prefix}_duplicate", ([point] * 1001).to_json, source],
                ["photos_#{prefix}_legacy", [point].to_json, source],
                ["photos_#{prefix}_null", 'null', source], ["photos_#{prefix}_nil_point", [point, nil].to_json, source],
                ["photos_#{prefix}_false_time", [point, point.merge(timestamp: true)].to_json, source],
                ["photos_#{prefix}_wrong", '{}', source]]
      [999, 1000, 1001, 2001].each do |count|
        bytes = count.times.map { |i| point.merge(timestamp: 1_768_519_800 + i) }.to_json
        cases << ["photos_#{prefix}_#{count}", bytes, source]
      end
      cases << ["photos_#{prefix}_failure", 2001.times.map do |i|
        point.merge(timestamp: i == 1000 ? 2_147_483_648 : 1_768_519_800 + i)
      end.to_json, source]
      cases << ["photos_#{prefix}_malformed", cases.last[1].delete_suffix(']'), source]
    end
    cases
  end
end
