# frozen_string_literal: true

module PlacesGoldenSupport
  VOLATILE = { 'x-request-id' => '00000000-0000-0000-0000-000000000000', 'x-runtime' => '0.000000',
               'set-cookie' => 'redacted' }.freeze

  def places_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{places_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      "[\n#{value.map { |v| "#{pad}#{places_exact_json(v, depth + 1)}" }.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def places_record(kase)
    oracle = ApiPlacesGoldenOracle
    travel_to(oracle::NOW) do
      places_seed(kase)
      oracle::SEQUENCES.each { |name, value| places_sql("SELECT setval('#{name}', #{value}, false)") }
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
      body = places_body(kase)
      headers = places_headers(kase, body)
      headers = places_conditional(kase[:path], headers) if kase[:conditional]
      target = kase[:auth] == :query ? "#{kase[:path]}?api_key=#{oracle::KEY}" : kase[:path]
      setup = places_snapshot(oracle::TABLES, oracle.setups)
      response = places_response(kase, target, headers, body)
      created = kase[:expect] == :own && response['status'] == 201
      { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => created ? ['etag'] : [],
        **(created ? { 'mask' => ['"created_at":"[^"]*"'] } : {}),
        'env' => kase[:env], 'setup' => setup,
        'request' => { 'method' => kase[:method].to_s.upcase, 'target' => target, 'headers' => headers.to_a,
                       'body' => body },
        'response' => response,
        **(places_after?(kase) ? { 'after' => places_rows(oracle::AFTER) } : {}) }
    end
  end

  def places_after?(kase)
    kase[:expect] == :own && kase[:method] != :get && !kase[:name].start_with?('auth_')
  end

  def places_body(kase)
    return '' unless kase.key?(:body)

    kase[:body].is_a?(String) ? kase[:body] : JSON.generate(kase[:body])
  end

  def places_headers(kase, body)
    headers = { 'Host' => 'localhost' }
    headers['Accept'] = 'application/json' unless kase[:accept] == :none
    headers.merge!(kase[:content]).merge!('Content-Length' => body.bytesize.to_s) unless body.empty?
    headers['Authorization'] = "Bearer #{ApiPlacesGoldenOracle::KEY}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4pl-golden-unknown' if kase[:auth] == :unknown
    headers.merge(kase[:headers] || {})
  end

  def places_conditional(target, headers)
    get target, headers: headers
    headers.merge('If-None-Match' => response.headers['ETag'])
  end

  def places_response(kase, target, headers, body)
    send(kase[:method], target, params: body.empty? ? nil : body, headers: headers.except('Content-Length'))
    headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    html = kase[:expect] == :rails && response.media_type == 'text/html'
    { 'status' => response.status, 'headers' => headers.merge(VOLATILE.slice(*headers.keys)),
      'body' => html ? '' : response.body }
  rescue StandardError
    raise unless kase[:expect] == :rails

    { 'status' => 500, 'headers' => {}, 'body' => '' }
  end

  def places_rows(tables)
    tables.to_h do |table|
      values = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, values.map { JSON.parse(_1).compact }]
    end
  end

  def places_snapshot(tables, setups)
    rows = places_rows(tables).to_a
    key = Digest::SHA256.hexdigest(JSON.generate(rows))[0, 16]
    setups[key] = rows
    key
  end

  def places_sql(sql) = ActiveRecord::Base.connection.execute(sql)

  def places_insert(table, row)
    connection = ActiveRecord::Base.connection
    columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
    values = row.values.map { connection.quote(_1.is_a?(Hash) ? JSON.generate(_1) : _1) }
    places_sql("INSERT INTO #{table} (#{columns}) VALUES (#{values.join(', ')})")
  end

  def places_seed(kase)
    oracle = ApiPlacesGoldenOracle
    user = { status: 1, timezone: 'UTC' }.merge(kase[:user] || {})
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    places_sql('TRUNCATE places CASCADE')
    places_insert('users', id: oracle::OWNER, email: 'places-owner@example.invalid', api_key: oracle::KEY,
                           status: user[:status], settings: { 'timezone' => user[:timezone] },
                           visits_redetected_at: oracle::STAMP, **stamps)
    places_insert('users', id: oracle::OTHER, email: 'places-other@example.invalid', api_key: 'phoenix-a4pl-other',
                           status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    places_seed_tags(stamps)
    return if kase[:seed] == :bare

    places_seed_places(stamps)
    places_seed_links(stamps)
  end

  def places_seed_tags(stamps)
    oracle = ApiPlacesGoldenOracle
    places_insert('tags', id: 950_101, user_id: oracle::OWNER, name: 'Home', icon: "\u{1F3E0}", color: '#ff0000',
                          privacy_radius_meters: 100, **stamps)
    places_insert('tags', id: 950_102, user_id: oracle::OWNER, name: 'Work', **stamps)
    places_insert('tags', id: 950_103, user_id: oracle::OTHER, name: 'Foreign', icon: 'x', color: '#000000', **stamps)
  end

  def places_seed_places(stamps)
    oracle = ApiPlacesGoldenOracle
    [[950_201, oracle::OWNER, 'Leipzig Hauptbahnhof', 51.345, 12.381, :coherent, 0,
      { note: 'platform 1', name_locked_at: '2026-09-01 12:00:00', city: 'Leipzig', country: 'Germany',
        geodata: { 'properties' => { 'osm_id' => 4711 } }, created_at: '2026-09-01 12:00:00.123456' }],
     [950_202, oracle::OWNER, 'Suggested place', 51.3397, 12.3731, :coherent, 1, {}],
     [950_203, oracle::OWNER, 'Legacy waypoint', 51.3333, 12.3833, nil, 2, {}],
     [950_204, oracle::OTHER, 'Foreign place', 51.34, 12.37, :coherent, 0, {}],
     [950_205, oracle::OWNER, 'Drifted', 51.35, 12.39, 'SRID=4326;POINT(12.4 51.4)', 0, {}],
     [950_206, oracle::OWNER, 'Café Riquet', 51.3399, 12.3768, :coherent, 0, {}],
     [950_207, oracle::OWNER, 'Hidden photon', 51.3385, 12.3755, :coherent, 1, {}]]
      .each do |id, user_id, name, lat, lon, lonlat, source, extra|
      lonlat = "SRID=4326;POINT(#{lon} #{lat})" if lonlat == :coherent
      places_insert('places', { id:, user_id:, name:, latitude: lat, longitude: lon, lonlat:, source:,
                                **stamps }.merge(extra))
    end
  end

  def places_seed_links(stamps)
    oracle = ApiPlacesGoldenOracle
    [[950_201, 950_102, '2026-09-01 10:00:00'], [950_201, 950_101, '2026-09-01 11:00:00'],
     [950_206, 950_101, '2026-09-01 10:00:00'], [950_204, 950_103, '2026-09-01 10:00:00']]
      .each_with_index do |(place, tag, at), i|
      places_insert('taggings', id: 950_601 + i, taggable_type: 'Place', taggable_id: place, tag_id: tag,
                                created_at: at, updated_at: at)
    end
    [[oracle::OWNER, 950_201, 1, nil], [oracle::OWNER, 950_202, 0, nil], [oracle::OWNER, 950_202, 1, nil],
     [oracle::OWNER, 950_202, 2, nil], [oracle::OWNER, 950_202, 1, oracle::STAMP], [oracle::OTHER, 950_201, 1, nil],
     [oracle::OWNER, nil, 0, nil]].each_with_index do |(user_id, place_id, status, deleted_at), i|
      started = "2026-08-0#{i + 1} 09:00:00"
      places_insert('visits', id: 950_301 + i, user_id:, place_id:, status:, deleted_at:, name: "Visit #{i + 1}",
                              started_at: started, ended_at: "2026-08-0#{i + 1} 10:00:00", duration: 60, **stamps)
    end
    places_insert('place_visits', id: 950_501, place_id: 950_201, visit_id: 950_307, **stamps)
    places_insert('place_visits', id: 950_502, place_id: 950_202, visit_id: 950_302, **stamps)
    [[950_401, 'Place', 950_201], [950_402, nil, nil], [950_403, 'Visit', 950_301]].each do |id, type, attachable|
      places_insert('notes', id:, user_id: oracle::OWNER, attachable_type: type, attachable_id: attachable,
                             body: "Leipzig note #{id}", noted_at: '2026-08-01 12:00:00', **stamps)
    end
  end
end
