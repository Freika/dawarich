# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: Rails GPX extraction' do
  def postgis_build
    full = ActiveRecord::Base.connection.select_value('SELECT postgis_full_version()')
    postgis = full[/POSTGIS="([^"\s]+)/, 1]
    proj = full[/PROJ="([^"\s]+)/, 1]
    "POSTGIS=#{postgis} PROJ=#{proj}"
  end

  def rows(sql, *binds)
    ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).map do |json|
      JSON.parse(json)
    end
  end

  def user_row(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, email, settings FROM users WHERE id = ?) x', user.id).first
  end

  def area_row(area)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, latitude, longitude, radius FROM areas ' \
         'WHERE id = ?) x', area.id).first
  end

  def place_row(place)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, ST_AsText(lonlat) AS lonlat_wkt, source, ' \
         'import_id, geodata::text AS geodata FROM places WHERE id = ?) x', place.id).first
  end

  def places_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, ST_AsText(lonlat) AS lonlat_wkt, source, ' \
         'import_id, geodata::text AS geodata FROM places WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def tag_row(tag)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, color, privacy_radius_meters FROM tags ' \
         'WHERE id = ?) x', tag.id).first
  end

  def tags_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, color, privacy_radius_meters FROM tags ' \
         'WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def visit_row(visit)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, area_id, place_id, started_at::text AS ' \
         'started_at, ended_at::text AS ended_at, duration, name, status FROM visits WHERE id = ?) x',
         visit.id).first
  end

  def taggings_for(user)
    rows(<<~SQL.squish, user.id)
      SELECT row_to_json(x)::text FROM (
        SELECT tg.id, tg.tag_id, tg.taggable_type, tg.taggable_id
        FROM taggings tg JOIN tags t ON t.id = tg.tag_id WHERE t.user_id = ? ORDER BY tg.id
      ) x
    SQL
  end

  # Rails sets started_at/completed_at from the wall clock; only whether the
  # call touched them is deterministic, never the value itself.
  def clock_state(value)
    value.present? ? 'set' : nil
  end

  def import_row(imp)
    row = rows(<<~SQL.squish, imp.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, name, source, additional_data_extraction_status,
               additional_data_extraction::text AS additional_data_extraction, raw_data::text AS raw_data
        FROM imports WHERE id = ?
      ) x
    SQL
    extraction = JSON.parse(row['additional_data_extraction'])
    %w[started_at completed_at].each { |key| extraction[key] = clock_state(extraction[key]) if extraction.key?(key) }
    row.merge('additional_data_extraction' => extraction)
  end

  def write_fixture(name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/enhanced_import/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(data.merge('postgis_build' => postgis_build))}\n")
  end

  def gpx_import(user, name, bytes, content_type: 'application/gpx+xml')
    import = create(:import, user: user, name: name, source: :gpx)
    import.file.attach(io: StringIO.new(bytes), filename: name, content_type: content_type)
    import
  end

  def extract_only(import)
    EnhancedImport::Adapters::GpxAdapter.new(import).translate.to_a
  end

  def run_extraction(import)
    EnhancedImport::ExtractJob.perform_now(import.id)
    import.reload
  end

  def wpt(lat:, lon:, name: nil, type: nil, color: nil)
    fields = []
    fields << "<name>#{name}</name>" if name
    fields << "<type>#{type}</type>" if type
    fields << "<color>#{color}</color>" if color
    "<wpt lat=\"#{lat}\" lon=\"#{lon}\">#{fields.join}</wpt>"
  end

  def gpx_doc(*waypoints)
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\">#{waypoints.join}</gpx>"
  end

  it 'seeks past a UTF-8 BOM and past leading junk before the document start' do
    user = create(:user, email: 'w5b-gpx-envelope@example.test')
    bom_body = "\xEF\xBB\xBF".b + gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'BOM Place'))
    junk_body = "garbage-before-xml\n#{gpx_doc(wpt(lat: 51.34, lon: 12.38, name: 'Junk Place'))}"

    bom_import = gpx_import(user, 'w5b-bom.gpx', bom_body)
    junk_import = gpx_import(user, 'w5b-junk.gpx', junk_body)

    bom_places = extract_only(bom_import)
    junk_places = extract_only(junk_import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(bom_import), import_row(junk_import)] },
      'expected' => {
        'bom_names' => bom_places.map(&:name),
        'junk_names' => junk_places.map(&:name)
      }
    }
    write_fixture('envelope_recovery', fixture)
  end

  it 'reads a g: namespaced wpt and an ISO-8859-1 encoded name' do
    user = create(:user, email: 'w5b-gpx-namespace-encoding@example.test')
    ns_body = <<~GPX
      <?xml version="1.0"?>
      <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1">
        <g:wpt lat="51.3397" lon="12.3731"><g:name>Namespaced Place</g:name></g:wpt>
      </g:gpx>
    GPX
    latin1_name = 'Café Mitte'.encode('ISO-8859-1')
    encoding_body = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" \
      "<gpx><wpt lat=\"51.34\" lon=\"12.38\"><name>#{latin1_name}</name></wpt></gpx>".encode('ISO-8859-1')

    ns_import = gpx_import(user, 'w5b-namespace.gpx', ns_body)
    encoding_import = gpx_import(user, 'w5b-latin1.gpx', encoding_body.b)

    ns_places = extract_only(ns_import)
    encoding_places = extract_only(encoding_import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(ns_import), import_row(encoding_import)] },
      'expected' => {
        'namespaced_name' => ns_places.first&.name,
        'iso_8859_1_name' => encoding_places.first&.name
      }
    }
    write_fixture('namespace_and_encoding', fixture)
  end

  it 'normalizes three colour shapes and drops one it cannot read' do
    user = create(:user, email: 'w5b-gpx-colours@example.test')
    body = gpx_doc(
      wpt(lat: 51.3397, lon: 12.3731, name: 'Three Digit', type: 'Food', color: '#0fc'),
      wpt(lat: 51.34, lon: 12.38, name: 'Six Digit', type: 'Food', color: '#10c0f0'),
      wpt(lat: 51.35, lon: 12.39, name: 'Eight Digit OsmAnd', type: 'Food', color: '#ffeecc22'),
      wpt(lat: 51.36, lon: 12.40, name: 'Unreadable', type: 'Food', color: 'chartreuse')
    )
    import = gpx_import(user, 'w5b-colours.gpx', body)
    places = extract_only(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)] },
      'expected' => { 'colours' => places.map { |p| { 'name' => p.name, 'tag_color' => p.tag_color } } }
    }
    write_fixture('colour_normalization', fixture)
  end

  it 'skips null island and a missing lat, but parses an underscore-separated and a hex coordinate' do
    user = create(:user, email: 'w5b-gpx-coordinates@example.test')
    body = gpx_doc(
      wpt(lat: '0.00001', lon: '0.00001', name: 'Null Island'),
      '<wpt lon="12.3731"><name>Missing Lat</name></wpt>',
      wpt(lat: '51.34', lon: '1_2.38', name: 'Underscore Coordinate'),
      wpt(lat: '0x1a', lon: '12.39', name: 'Hex Coordinate')
    )
    import = gpx_import(user, 'w5b-coordinates.gpx', body)
    places = extract_only(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)] },
      'expected' => {
        'emitted' => places.map { |p| { 'name' => p.name, 'latitude' => p.latitude, 'longitude' => p.longitude } }
      }
    }
    write_fixture('coordinate_edge_cases', fixture)
  end

  it 'proves the decimal-cast divergence on a waypoint at the Finding-13 probe latitude' do
    user = create(:user, email: 'w5b-gpx-decimal-cast@example.test')
    probe_lat = '51.33971249996'
    body = gpx_doc(wpt(lat: probe_lat, lon: '12.3731', name: 'Decimal Cast Probe'))
    import = gpx_import(user, 'w5b-decimal-cast.gpx', body)

    column_type = Place.type_for_attribute('latitude')
    parsed_lat = Float(probe_lat)
    expect(BigDecimal(parsed_lat, 10).round(6)).not_to eq(column_type.cast(parsed_lat))

    run_extraction(import)
    place = Place.where(user_id: user.id).order(:id).last

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)] },
      'decimal_cast' => { 'parsed_lat' => parsed_lat,
                          'bigdecimal_round6' => BigDecimal(parsed_lat, 10).round(6).to_s('F'),
                          'column_cast' => column_type.cast(parsed_lat).to_s('F') },
      'expected' => { 'place_lonlat_wkt' => places_for(user).first['lonlat_wkt'], 'place_id_present' => !place.nil? }
    }
    write_fixture('decimal_cast_waypoint', fixture)
  end

  it 'folds a repeated waypoint, renames a pin within 1 m, and reuses a same-name place within 75 m' do
    user = create(:user, email: 'w5b-gpx-writer-dedup@example.test')

    existing_pin = create(:place, user: user, name: 'Old Pin Name', latitude: 51.3397, longitude: 12.3731,
                                   source: :gpx_waypoint)
    existing_named = create(:place, user: user, name: 'Shared Name', latitude: 51.4000, longitude: 12.5000,
                                     source: :manual)
    places_before = [place_row(existing_pin), place_row(existing_named)]

    body = gpx_doc(
      wpt(lat: 51.3402, lon: 12.3735, name: 'Repeat Me'),
      wpt(lat: 51.3402, lon: 12.3735, name: 'Repeat Me'),
      wpt(lat: 51.3397, lon: 12.3731, name: 'Renamed Pin'),
      wpt(lat: 51.40003, lon: 12.50004, name: 'Shared Name')
    )
    import = gpx_import(user, 'w5b-writer-dedup.gpx', body)
    run_extraction(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)], 'places' => places_before },
      'expected' => { 'places' => places_for(user) }
    }
    write_fixture('writer_dedup', fixture)
  end

  it 'reuses an existing tag by case-insensitive name and skips attaching a privacy-zone tag' do
    user = create(:user, email: 'w5b-gpx-tags@example.test')
    reused_tag = create(:tag, user: user, name: 'Cafe', color: '#112233')
    privacy_tag = create(:tag, user: user, name: 'Home Zone', color: '#334455', privacy_radius_meters: 100)
    tags_before = [tag_row(reused_tag), tag_row(privacy_tag)]

    body = gpx_doc(
      wpt(lat: 51.3397, lon: 12.3731, name: 'Case Insensitive Tag', type: 'CAFE'),
      wpt(lat: 51.35, lon: 12.39, name: 'Privacy Zone Place', type: 'Home Zone')
    )
    import = gpx_import(user, 'w5b-tags.gpx', body)
    run_extraction(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)], 'tags' => tags_before },
      'expected' => { 'tags' => tags_for(user), 'taggings' => taggings_for(user), 'places' => places_for(user) }
    }
    write_fixture('tag_reuse_and_privacy', fixture)
  end

  it 'truncates a name over 255 characters instead of raising' do
    user = create(:user, email: 'w5b-gpx-long-name@example.test')
    long_name = 'B' * 300
    body = gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: long_name))
    import = gpx_import(user, 'w5b-long-name.gpx', body)
    run_extraction(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)] },
      'expected' => { 'places' => places_for(user) }
    }
    write_fixture('name_over_limit', fixture)
  end

  it 'extracts a zipped single entry whose first archive member is a directory' do
    user = create(:user, email: 'w5b-gpx-zip@example.test')
    body = gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Zipped Place'))
    zip_path = Rails.root.join('tmp', "w5b-zip-#{SecureRandom.hex(4)}.zip")
    Zip::File.open(zip_path.to_s, create: true) do |zf|
      zf.mkdir('waypoints/')
      zf.get_output_stream('favourites.gpx') { |f| f.write(body) }
    end
    zip_bytes = File.binread(zip_path)
    File.delete(zip_path)

    import = gpx_import(user, 'w5b-zip.gpx', zip_bytes, content_type: 'application/zip')
    run_extraction(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_row(import)] },
      'expected' => { 'places' => places_for(user) }
    }
    write_fixture('zipped_single_entry', fixture)
  end

  it 'skips extraction entirely when raw_data already records zero waypoints seen' do
    user = create(:user, email: 'w5b-gpx-zero-waypoints@example.test')
    body = gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Should Not Extract'))
    import = create(:import, user: user, name: 'w5b-zero-waypoints.gpx', source: :gpx,
                             raw_data: { 'waypoints_seen' => 0 })
    import.file.attach(io: StringIO.new(body), filename: 'w5b-zero-waypoints.gpx',
                       content_type: 'application/gpx+xml')
    import_before = import_row(import)

    run_extraction(import)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [import_before] },
      'expected' => { 'places' => places_for(user), 'import' => import_row(import) }
    }
    write_fixture('waypoints_seen_zero', fixture)
  end

  it 'undoes an extraction but keeps a place a visit has since claimed' do
    user = create(:user, email: 'w5b-gpx-undo@example.test')
    body = gpx_doc(
      wpt(lat: 51.3397, lon: 12.3731, name: 'Kept By Visit'),
      wpt(lat: 51.40, lon: 12.50, name: 'Removed On Undo')
    )
    import = gpx_import(user, 'w5b-undo.gpx', body)
    run_extraction(import)

    kept_place = Place.where(user_id: user.id, name: 'Kept By Visit').first
    area = create(:area, user: user, latitude: 51.3397, longitude: 12.3731, radius: 50)
    visit = create(:visit, user: user, area: area, place: kept_place, status: :confirmed,
                           started_at: Time.zone.at(1_790_000_000), ended_at: Time.zone.at(1_790_003_600))

    places_before = places_for(user)
    EnhancedImport::Destroy.new(import).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'areas' => [area_row(area)], 'imports' => [import_row(import)],
                   'places' => places_before, 'visits' => [visit_row(visit)] },
      'expected' => { 'places_after' => places_for(user) }
    }
    write_fixture('undo_keeps_visited_place', fixture)
  end
end
