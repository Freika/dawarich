# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def tcx_point(time = '2026-01-15T23:30:00Z', extra = '')
    "<Trackpoint><Time>#{time}</Time><Position><LatitudeDegrees>51.3001</LatitudeDegrees>" \
      '<LongitudeDegrees>12.4001</LongitudeDegrees></Position><AltitudeMeters>12.75</AltitudeMeters>' \
      "#{extra}</Trackpoint>"
  end

  def tcx_document(body)
    '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" ' \
      "xmlns:x=\"urn:speed\"><Activities>#{body}</Activities></TrainingCenterDatabase>"
  end

  def tcx_activity(points, sport = 'Running')
    "<Activity Sport=\"#{sport}\"><Lap><Track>#{points}</Track></Lap></Activity>"
  end

  def tcx_cases
    speed = '<Extensions><x:TPX><x:Speed>3.25</x:Speed></x:TPX></Extensions>'
    point = tcx_point('2026-01-15T23:30:00Z', speed)
    multi = tcx_activity(point) + tcx_activity(tcx_point('2026-01-15T23:30:01Z'), 'Biking') +
            tcx_activity(tcx_point('2026-01-15T23:30:02Z'), 'Other')
    missing = [point, point.sub(%r{<Time>.*?</Time>}, '').sub('12.4001', '13.4001'),
               point.sub(%r{<Position>.*?</Position>}, ''),
               point.sub(%r{<LatitudeDegrees>.*?</LatitudeDegrees>}, ''),
               point.sub(%r{<LongitudeDegrees>.*?</LongitudeDegrees>}, ''),
               point.sub(%r{<Time>.*?</Time>}, '<Time> </Time>').sub('12.4001', '14.4001')].join
    first_track = tcx_point('2026-01-15T23:30:01Z')
    second_lap = tcx_point('2026-01-15T23:30:02Z')
    laps = "<Activity Sport=\"Running\"><Lap><Track>#{point}</Track><Track>#{first_track}</Track></Lap>" \
           "<Lap><Track>#{second_lap}</Track></Lap></Activity>"
    cases = [['tcx_import_singleton', tcx_document(tcx_activity(point)), 'UTC'],
             ['tcx_import_multiple', tcx_document(multi), 'UTC'],
             ['tcx_import_laps', tcx_document(laps), 'UTC'],
             ['tcx_import_missing', tcx_document(tcx_activity(missing)), 'UTC'],
             ['tcx_import_empty', tcx_document(''), 'UTC'],
             ['tcx_import_legacy', tcx_document(tcx_activity(point)), 'UTC'],
             ['tcx_import_ampersands', tcx_document("<Notes>Road & Hill &bogus;</Notes>#{multi}"), 'UTC'],
             ['tcx_import_cdata', tcx_document(tcx_activity(point.sub('51.3001', '<![CDATA[51.3001]]>'))), 'UTC'],
             ['tcx_import_nil_altitude',
              tcx_document(tcx_activity(point.sub(%r{<AltitudeMeters>.*?</AltitudeMeters>}, ''))), 'UTC'],
             ['tcx_import_invalid_numbers',
              tcx_document(tcx_activity(point.gsub('51.3001', 'wrong').gsub('3.25', 'bad'))), 'UTC'],
             ['tcx_import_malformed', tcx_document(tcx_activity(point)).sub('</TrainingCenterDatabase>', '<broken>'),
              'UTC'],
             ['tcx_import_bad_time', tcx_document(tcx_activity(point + tcx_point('bad'))), 'UTC']]
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["tcx_import_time_#{zone.tr('/', '_')}", tcx_document(tcx_activity(tcx_point('2026-01-15 23:30:00'))),
                zone]
    end
    [999, 1000, 1001, 2001].each do |count|
      points = count.times.map { |i| tcx_point((Time.current + i).iso8601) }.join
      cases << ["tcx_import_#{count}", tcx_document(tcx_activity(points)), 'UTC']
    end
    cases << ['tcx_import_duplicate', tcx_document(tcx_activity(point * 1001)), 'UTC']
    cases << ['tcx_import_failure', tcx_document(tcx_activity(1000.times.map do |i|
      tcx_point((Time.current + i).iso8601)
    end.join + tcx_point((Time.current + 1000).iso8601).sub('12.75', '100000000'))), 'UTC']
    cases
  end
end
