# frozen_string_literal: true

module FamilyWritesGoldenSupport
  def writes_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{writes_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      "[\n#{value.map { |v| "#{pad}#{writes_exact_json(v, depth + 1)}" }.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def writes_record(kase)
    oracle = ApiFamilyWritesOracle
    travel_to(oracle::NOW) do
      writes_seed(kase)
      oracle::SEQUENCES.each { |name, value| writes_sql("SELECT setval('#{name}', #{value}, false)") }
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
      body = writes_body(kase)
      headers = writes_headers(kase, body)
      setup = writes_snapshot(oracle::TABLES, oracle.setups)
      response = writes_response(kase, headers, body)
      unordered = kase[:expect] == :own && response['body'].start_with?('{"members"', '{"lapsed"') ? ['members'] : []
      { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => ['etag'], 'unordered' => unordered,
        'env' => kase[:env],
        'setup' => setup,
        'request' => { 'method' => kase[:method].to_s.upcase, 'target' => kase[:path], 'headers' => headers.to_a,
                       'body' => body },
        'response' => response, 'after' => writes_rows(oracle::AFTER), 'jobs' => writes_jobs }
    end
  end

  def writes_body(kase)
    return '' unless kase.key?(:body)

    kase[:body].is_a?(String) ? kase[:body] : JSON.generate(kase[:body])
  end

  def writes_headers(kase, body)
    headers = { 'Host' => 'localhost', 'Accept' => 'application/json' }
    headers.merge!(kase[:content]).merge!('Content-Length' => body.bytesize.to_s) unless body.empty?
    headers['Authorization'] = "Bearer #{ApiFamilyWritesOracle::KEY}" if kase[:auth] == :bearer
    headers
  end

  def writes_response(kase, headers, body)
    params = body.empty? ? nil : body
    send(kase[:method], kase[:path], params:, headers: headers.except('Content-Length'))
    headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    html = kase[:expect] == :rails && response.media_type == 'text/html'
    { 'status' => response.status, 'headers' => headers,
      'body' => html ? '' : response.body.gsub(/token=[\w.-]+/, 'token=redacted') }
  rescue StandardError
    raise unless kase[:expect] == :rails

    { 'status' => 500, 'headers' => {}, 'body' => '' }
  end

  def writes_jobs
    enqueued_jobs.map do |job|
      gid = job[:args].to_s[%r{gid://[^/]+/([\w:]+/\d+)}, 1]
      [job[:job].to_s, job[:args].first(2).grep(String), gid].flatten.compact
    end
  end

  def writes_rows(tables)
    tables.to_h do |table|
      values = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, values.map { JSON.parse(_1).compact }]
    end
  end

  def writes_snapshot(tables, setups)
    rows = writes_rows(tables).to_a
    key = Digest::SHA256.hexdigest(JSON.generate(rows))[0, 16]
    setups[key] = rows
    key
  end

  def writes_sql(sql) = ActiveRecord::Base.connection.execute(sql)

  def writes_insert(table, row)
    connection = ActiveRecord::Base.connection
    columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
    values = row.values.map { connection.quote(_1.is_a?(Hash) || _1.is_a?(Array) ? JSON.generate(_1) : _1) }
    writes_sql("INSERT INTO #{table} (#{columns}) VALUES (#{values.join(', ')})")
  end

  def writes_settings(timezone, share, extra = {})
    settings = { 'timezone' => timezone }.merge(extra)
    settings['family'] = { 'location_sharing' => share } unless share.nil?
    settings
  end

  def writes_seed(kase)
    oracle = ApiFamilyWritesOracle
    actor = { timezone: 'UTC', share: oracle::SHARE.merge('enabled' => false), extra: {} }.merge(kase[:actor] || {})
    member = { share: oracle::SHARE, locale: nil }.merge(kase[:member] || {})
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP, visits_redetected_at: oracle::STAMP }
    member_extra = member[:locale] ? { 'locale' => member[:locale] } : {}
    writes_insert('users', id: oracle::OWNER, email: 'writes-owner@example.invalid', api_key: oracle::KEY, status: 1,
                           settings: writes_settings(actor[:timezone], actor[:share], actor[:extra]), **stamps)
    writes_insert('users', id: oracle::MEMBER, email: 'writes-member@example.invalid', api_key: 'phoenix-a4fam-w2',
                           status: 1, settings: writes_settings('UTC', member[:share], member_extra), **stamps)
    writes_insert('users', id: oracle::STRANGER, email: 'writes-stranger@example.invalid', api_key: 'phoenix-a4fam-w3',
                           status: 1, settings: writes_settings('UTC', oracle::SHARE), **stamps)
    writes_insert('users', id: oracle::GONE, email: 'writes-gone@example.invalid', api_key: 'phoenix-a4fam-w4',
                           status: 1, deleted_at: oracle::STAMP, settings: writes_settings('UTC', nil), **stamps)
    writes_seed_family(kase)
    writes_seed_points if kase[:points]
  end

  def writes_seed_family(kase)
    oracle = ApiFamilyWritesOracle
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    writes_insert('families', id: oracle::FAMILY, name: 'Leipzig writers', creator_id: oracle::OWNER, **stamps)
    writes_insert('families', id: oracle::FAMILY + 1, name: 'Elsewhere', creator_id: oracle::STRANGER, **stamps)
    roles = [[oracle::OWNER, 0], [oracle::MEMBER, 1], [oracle::GONE, 1], [oracle::STRANGER, 0]]
    roles.each_with_index do |(user_id, role), i|
      next if user_id == oracle::OWNER && kase[:seed] == :no_family

      family_id = user_id == oracle::STRANGER ? oracle::FAMILY + 1 : oracle::FAMILY
      writes_insert('family_memberships', id: 893_001 + i, family_id:, user_id:, role:,
                                          created_at: "2029-12-0#{i + 1} 09:15:30", updated_at: oracle::STAMP)
    end
    (kase[:requests] || []).each { writes_seed_request(_1) }
  end

  def writes_seed_request(spec)
    now = ApiFamilyWritesOracle::NOW
    writes_insert('family_location_requests',
                  id: spec[:id], requester_id: spec[:requester], target_user_id: spec[:target],
                  family_id: ApiFamilyWritesOracle::FAMILY, status: spec[:status] || 0,
                  suggested_duration: spec[:suggested] || '24h', expires_at: now + spec[:expires],
                  created_at: now + spec[:created], updated_at: now + spec[:created])
  end

  def writes_seed_points
    oracle = ApiFamilyWritesOracle
    t = oracle::NOW.to_i
    [[-3600, {}], [-30 * 3600, {}], [-60 * 3600, {}], [-100 * 3600, {}], [-200 * 3600, {}],
     [-1800, { anomaly: true }], [-2400, { lonlat: nil }], [-50 * 3600, { user_id: oracle::OWNER }]]
      .each_with_index do |(offset, extra), i|
      row = { id: 894_001 + i, user_id: oracle::MEMBER, timestamp: t + offset,
              lonlat: "SRID=4326;POINT(12.36#{i}25 51.33#{i}75)", created_at: oracle::STAMP, updated_at: oracle::STAMP }
      writes_insert('points', row.merge(extra))
    end
  end
end
