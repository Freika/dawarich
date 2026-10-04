# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def kml_document(body, namespaces = 'xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2"')
    "<?xml version=\"1.0\"?><kml #{namespaces}><Document>#{body}</Document></kml>"
  end

  def kml_placemark(coordinates, time = '2026-01-15T23:30:00Z', type = 'Point')
    "<Placemark><TimeStamp><when>#{time}</when></TimeStamp><#{type}><coordinates>#{coordinates}</coordinates>" \
      "</#{type}></Placemark>"
  end

  def kml_cases
    point = kml_placemark('12.4,51.3,12.75')
    multi = '<Placemark><TimeSpan><end>2026-01-15T23:30:01Z</end></TimeSpan>' \
            '<ExtendedData><Data name="Speed"><value>3.25</value></Data></ExtendedData><MultiGeometry>' \
            '<Point><coordinates>12.5,51.4,1.5 12.6,51.5,2.5</coordinates></Point>' \
            '<LineString><coordinates>12.7,51.6,3.5 12.8,51.7,4.5</coordinates></LineString>' \
            '</MultiGeometry></Placemark>'
    track = '<gx:Track><when>2026-01-15T23:31:00Z</when><when>bad</when>' \
            '<when>2026-01-15T23:31:02Z</when><gx:coord>12.9 51.8 8.75</gx:coord>' \
            '<gx:coord>13 51.9 9.75</gx:coord><gx:coord>13.1 52</gx:coord>' \
            '<gx:coord>13.2 52.1 10</gx:coord></gx:Track>'
    named = '<Placemark><name>2026-01-15 23:30 - 2026-01-15 23:31</name><ExtendedData>' \
            '<Data name="speed"><value>4.25</value></Data></ExtendedData>' \
            '<LineString><coordinates>12.4,51.3 12.5,51.4,2.75 12.6,51.5,3.5 12.7,51.6,4</coordinates>' \
            '</LineString></Placemark>'
    cases = [['kml_import_empty', kml_document(''), 'UTC'],
             ['kml_import_all', kml_document(point + multi + track), 'UTC'],
             ['kml_import_no_namespace', kml_document(point + named, ''), 'UTC'],
             ['kml_import_prefixed', kml_document(point.gsub(%r{(/?)(Placemark|TimeStamp|when|Point|coordinates)},
                                                             '\1k:\2'), 'xmlns:k="urn:other"'), 'UTC'],
             ['kml_import_tracks_short_times', kml_document(track.sub('<when>bad</when>', '')
                                                              .sub('<when>2026-01-15T23:31:02Z</when>', '')), 'UTC'],
             ['kml_import_tracks_short_coords', kml_document(track.sub('<gx:coord>13.1 52</gx:coord>', '')
                                                               .sub('<gx:coord>13.2 52.1 10</gx:coord>', '')), 'UTC'],
             ['kml_import_legacy', kml_document(point), 'UTC'],
             ['kml_import_missing', kml_document('<Placemark><Point><coordinates>12,51</coordinates></Point>' \
                                                '</Placemark>'), 'UTC'],
             ['kml_import_invalid_time', kml_document(kml_placemark('12.4,51.3', 'bad')), 'UTC'],
             ['kml_import_invalid_coords', kml_document(kml_placemark('bad,wrong one 12.4,51.3')), 'UTC'],
             ['kml_import_ampersands', kml_document("<name>Road & Hill &bogus; &#0;</name>#{point}"), 'UTC'],
             ['kml_import_cdata', kml_document(point.sub('12.4,51.3,12.75', '<![CDATA[12.4,51.3,12.75]]>')), 'UTC']]
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      cases << ["kml_import_named_#{zone.tr('/', '_')}", kml_document(named), zone]
    end
    [999, 1000, 1001, 2001].each do |count|
      body = count.times.map { |i| kml_placemark('12.4,51.3,12.75', (Time.current + i).iso8601) }.join
      cases << ["kml_import_#{count}", kml_document(body), 'UTC']
    end
    cases << ['kml_import_duplicate', kml_document(point * 1001), 'UTC']
    cases << ['kml_import_malformed', cases[-2][1].sub('</kml>', '<broken></kml>'), 'UTC']
    cases << ['kml_import_bad_tail', "#{cases[-3][1]}<broken>", 'UTC']
    cases << ['kml_import_failure', kml_document(1000.times.map do |i|
      kml_placemark('12.4,51.3,12.75', (Time.current + i).iso8601)
    end.join + kml_placemark('12.4,51.3,100000000', (Time.current + 1000).iso8601)), 'UTC']
    cases << ['kml_import_late_time', kml_document(1000.times.map do |i|
      kml_placemark('12.4,51.3,12.75', (Time.current + i).iso8601)
    end.join + kml_placemark('12.4,51.3', 'bad')), 'UTC']
    cases << ['kml_import_large_line', kml_document(kml_placemark(['12.4,51.3,12.75'] * 1001 * ' ',
                                                                  '2026-01-15T23:30:00Z', 'LineString')), 'UTC']
    cases << ['kml_import_spooled_line', kml_document(kml_placemark(['12.4,51.3,12.75'] * 75_000 * ' ',
                                                                    '2026-01-15T23:30:00Z', 'LineString')), 'UTC']
    cases
  end
end
