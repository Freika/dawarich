# frozen_string_literal: true

module Wave5bFixtureSupport
  GEOCODING_ENV = %w[
    PHOTON_API_HOST PHOTON_API_KEY PHOTON_API_USE_HTTPS GEOAPIFY_API_KEY NOMINATIM_API_HOST NOMINATIM_API_KEY
    NOMINATIM_API_USE_HTTPS LOCATIONIQ_API_KEY REVERSE_GEOCODING_RPS STORE_GEODATA
  ].freeze
  LEIPZIG_LAT = 51.3397
  LEIPZIG_LON = 12.3731
  BASE_TS = 1_790_000_000

  def self.assert_geocoding_env_blank!
    pinned = GEOCODING_ENV.reject { |name| ENV.fetch(name, '').strip.empty? }
    raise "geocoding environment variables must be blank: #{pinned.join(', ')}" if pinned.any?
  end

  def self.included(base)
    base.before(:all) { Wave5bFixtureSupport.assert_geocoding_env_blank! }
    base.after { WebMock.reset_callbacks }
  end

  def postgis_build
    full = ActiveRecord::Base.connection.select_value('SELECT postgis_full_version()')
    "POSTGIS=#{full[/POSTGIS="([^"\s]+)/, 1]} PROJ=#{full[/PROJ="([^"\s]+)/, 1]}"
  end

  def rows(sql, *binds)
    ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).map do |json|
      JSON.parse(json)
    end
  end

  def clock_state(value)
    value.present? ? 'set' : nil
  end

  def user_row(user)
    row = rows(<<~SQL.squish, user.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, email, settings, visits_redetected_at::text AS visits_redetected_at FROM users WHERE id = ?
      ) x
    SQL
    row.merge('visits_redetected_at' => clock_state(row['visits_redetected_at']))
  end

  def instance_setting_rows
    rows(<<~SQL.squish)
      SELECT row_to_json(x)::text FROM (
        SELECT id, key, value::text AS value, encrypted_value FROM instance_settings ORDER BY id
      ) x
    SQL
  end

  def places_for(user)
    rows(<<~SQL.squish, user.id).map { |row| place_clocks(row) }
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, name, latitude::text AS latitude, longitude::text AS longitude,
               ST_AsText(lonlat) AS lonlat_wkt, city, country, source, import_id, demo, note,
               geodata::text AS geodata, name_locked_at::text AS name_locked_at,
               reverse_geocoded_at::text AS reverse_geocoded_at
        FROM places WHERE user_id = ? ORDER BY id
      ) x
    SQL
  end

  def place_clocks(row)
    row.merge('name_locked_at' => clock_state(row['name_locked_at']),
              'reverse_geocoded_at' => clock_state(row['reverse_geocoded_at']))
  end

  def areas_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, latitude::text AS latitude, ' \
         'longitude::text AS longitude, radius FROM areas WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def tags_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, color, privacy_radius_meters, demo ' \
         'FROM tags WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def taggings_for(user)
    rows(<<~SQL.squish, user.id)
      SELECT row_to_json(x)::text FROM (
        SELECT tg.id, tg.tag_id, tg.taggable_type, tg.taggable_id
        FROM taggings tg JOIN tags t ON t.id = tg.tag_id WHERE t.user_id = ? ORDER BY tg.id
      ) x
    SQL
  end

  def plain(value)
    case value
    when ActiveRecord::Base then value.id
    when Hash then value.to_h { |key, item| [key.to_s, plain(item)] }
    when Array then value.map { |item| plain(item) }
    when Symbol then value.to_s
    when BigDecimal then value.to_s('F')
    else value
    end
  end

  def write_fixture(dir, name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/#{dir}/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(data.merge('postgis_build' => postgis_build))}\n")
  end

  def base_ts = BASE_TS
  def leipzig_lat(offset = 0.0) = (LEIPZIG_LAT + offset).round(6)
  def leipzig_lon(offset = 0.0) = (LEIPZIG_LON + offset).round(6)

  def leipzig(offset_lat = 0.0, offset_lon = 0.0)
    "POINT(#{leipzig_lon(offset_lon)} #{leipzig_lat(offset_lat)})"
  end

  def record_http!
    log = []
    WebMock.after_request do |signature, response|
      entry = { 'method' => signature.method.to_s, 'url' => request_url(signature.uri),
                'headers' => signature.headers.to_h.except('User-Agent') }
      entry.merge!(response.should_timeout ? { 'timeout' => true } : response_fields(response))
      log << entry
    end
    log
  end

  def request_url(uri)
    uri.port == uri.default_port ? uri.omit(:port).to_s : uri.to_s
  end

  def response_fields(response)
    { 'status' => response.status.first, 'body' => response.body.to_s }
  end

  def geocoder_cache
    store = Geocoder.config.cache
    store.keys('http*').sort.map { |key| { 'key' => key, 'value' => store.get(key) } }
  end

  def json_response(body, status: 200)
    { status: status, body: body.is_a?(String) ? body : body.to_json,
headers: { 'Content-Type' => 'application/json' } }
  end

  def enqueued(job_class)
    enqueued_jobs.select { |job| job[:job] == job_class }.map { |job| job[:args] }
  end
end
