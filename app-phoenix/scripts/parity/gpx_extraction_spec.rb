# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'
require_relative 'wave5b_fixture_support'

RSpec.describe 'Phoenix fixture: Rails GPX extraction' do
  include FixtureRecording::DeterministicInputs

  def fixture_models
    [User, Import, Export, ActiveStorage::Blob, ActiveStorage::Attachment, Place, Visit, Point, Tag, Tagging,
     PlaceVisit, Note, Area, Track, TrackSegment, Notification, ActionText::RichText, Trip]
  end

  closure_cases = {}
  define_method(:write_fixture) do |directory, name, data|
    closure_cases[name] = data.merge('postgis_build' => postgis_build)
    super(directory, name, data)
  end
  after(:all) do
    FixtureRecording.verify(Rails.root.join('app-phoenix/test/fixtures/imports/formats/a12f3a-f18.json'),
                            "#{JSON.pretty_generate(closure_cases.sort.to_h)}\n")
  end

  include Wave5bFixtureSupport
  include ActiveSupport::Testing::TimeHelpers

  let!(:effects) { capture_import_effects! }

  def capture_import_effects!
    captured = { 'kinds' => [], 'card_statuses' => [] }
    allow(EnhancedImport::CardBroadcaster).to receive(:call).and_wrap_original do |original, import|
      captured['kinds'] << import_kind('enhanced_import_card', import)
      captured['card_statuses'] << Import.where(id: import.id).pick(Arel.sql('additional_data_extraction_status'))
      original.call(import)
    end
    allow_any_instance_of(Import).to receive(:schedule_untracked_track_generation).and_wrap_original do |original|
      captured['kinds'] << import_kind('schedule_untracked_tracks', original.receiver)
      original.call
    end
    captured
  end

  def import_kind(kind, import)
    { 'kind' => kind, 'payload' => { 'user_id' => import.user_id, 'import_id' => import.id } }
  end

  def import_row(import)
    row = rows(<<~SQL.squish, import.id).first
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

  def file_row(import)
    blob = import.file.blob
    { 'import_id' => import.id, 'filename' => blob.filename.to_s, 'content_type' => blob.content_type,
      'byte_size' => blob.byte_size, 'checksum' => blob.checksum, 'base64' => Base64.strict_encode64(blob.download) }
  end

  def visit_rows(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, area_id, place_id, ' \
         'floor(extract(epoch FROM started_at))::bigint AS started_at, ' \
         'floor(extract(epoch FROM ended_at))::bigint AS ended_at, duration, name, status ' \
         'FROM visits WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def place_visit_rows(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT pv.id, pv.place_id, pv.visit_id FROM place_visits pv ' \
         'JOIN places p ON p.id = pv.place_id WHERE p.user_id = ? ORDER BY pv.id) x', user.id)
  end

  def note_rows(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, attachable_type, attachable_id, body, ' \
         'floor(extract(epoch FROM noted_at))::bigint AS noted_at FROM notes WHERE user_id = ? ORDER BY id) x',
         user.id)
  end

  def gpx_import(user, name, bytes, content_type: 'application/gpx+xml', raw_data: nil)
    import = create(:import, user:, name:, source: :gpx, raw_data:)
    import.file.attach(io: StringIO.new(bytes), filename: name, content_type:)
    import
  end

  def extracted_items(import)
    EnhancedImport::Adapters::GpxAdapter.new(import).translate.to_a.map { |place| plain(place.to_h) }
  end

  def extract_fixture(name, user, imports)
    input = { 'users' => [user_row(user)], 'imports' => imports.map { |import| import_row(import) } }
    extracted = imports.map { |import| { 'import_id' => import.id, 'items' => extracted_items(import) } }
    fixture = { 'input' => input, 'files' => imports.map { |import| file_row(import) },
                'expected' => { 'extracted' => extracted } }
    write_fixture('enhanced_import', name, fixture)
  end

  def writer_snapshot(user)
    { 'places' => places_for(user), 'tags' => tags_for(user), 'taggings' => taggings_for(user) }
  end

  def writer_fixture(name, user, import, extra_expected = {})
    input = { 'users' => [user_row(user)], 'imports' => [import_row(import)] }.merge(writer_snapshot(user))
    files = [file_row(import)]
    extracted = extracted_items(import)
    EnhancedImport::ExtractJob.perform_now(import.id)
    expected = { 'import' => import_row(import.reload) }.merge(writer_snapshot(user), 'effects' => effects)
    fixture = { 'input' => input.reject { |_table, table_rows| table_rows.empty? }, 'files' => files,
                'extracted' => extracted, 'expected' => expected.merge(extra_expected) }
    write_fixture('enhanced_import', name, fixture)
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

  def zip_bytes(entries)
    path = Rails.root.join('tmp', "w5b-zip-#{SecureRandom.hex(4)}.zip")
    previous = Time.current
    travel_to Time.utc(2026, 9, 1)
    Zip::File.open(path.to_s, create: true) do |zip|
      entries.each { |entry, body| body.nil? ? zip.mkdir(entry) : zip.get_output_stream(entry) { |f| f.write(body) } }
    end
    File.binread(path)
  ensure
    File.delete(path) if path && File.exist?(path)
    travel_to(previous) if previous
  end

  it 'seeks past a UTF-8 BOM and past leading junk before the document start' do
    user = create(:user, email: 'w5b-gpx-envelope@example.test')
    bom = gpx_import(user, 'w5b-bom.gpx',
                     "\xEF\xBB\xBF".b + gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'BOM Place')))
    junk = gpx_import(user, 'w5b-junk.gpx', "garbage-before-xml\n#{gpx_doc(wpt(lat: 51.34, lon: 12.38, name: 'Junk'))}")
    extract_fixture('envelope_recovery', user, [bom, junk])
  end

  it 'reads a g: namespaced wpt, an ISO-8859-1 encoded name and a UTF-16 document with a BOM' do
    user = create(:user, email: 'w5b-gpx-namespace-encoding@example.test')
    namespaced = gpx_import(user, 'w5b-namespace.gpx', <<~GPX)
      <?xml version="1.0"?>
      <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1">
        <g:wpt lat="51.3397" lon="12.3731"><g:name>Namespaced Place</g:name></g:wpt>
      </g:gpx>
    GPX
    latin1 = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n" \
             '<gpx><wpt lat="51.34" lon="12.38"><name>Café Mitte</name></wpt></gpx>'.encode('ISO-8859-1')
    utf16 = "\uFEFF<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n" \
            '<gpx><wpt lat="51.345" lon="12.385"><name>Wide Place</name></wpt></gpx>'.encode('UTF-16LE')
    imports = [namespaced, gpx_import(user, 'w5b-latin1.gpx', latin1.b), gpx_import(user, 'w5b-utf16.gpx', utf16.b)]
    extract_fixture('namespace_and_encoding', user, imports)
  end

  it 'stops at a truncated attribute, a mismatched end tag and an undefined entity, and drops a CDATA name' do
    user = create(:user, email: 'w5b-gpx-malformed@example.test')
    first = wpt(lat: 51.3397, lon: 12.3731, name: 'Before The Break')
    documents = {
      'w5b-truncated-attribute.gpx' => "#{gpx_doc(first)[0..-7]}<wpt lat=\"51.34",
      'w5b-mismatched-end.gpx' => gpx_doc(first, '<wpt lat="51.34" lon="12.38"><name>Broken</nam></wpt>',
                                          wpt(lat: 51.35, lon: 12.39, name: 'After')),
      'w5b-undefined-entity.gpx' => gpx_doc(first, '<wpt lat="51.34" lon="12.38"><name>Caf&eacute;</name></wpt>',
                                            wpt(lat: 51.35, lon: 12.39, name: 'After')),
      'w5b-cdata-name.gpx' => gpx_doc('<wpt lat="51.3397" lon="12.3731"><name><![CDATA[Cdata <Place>]]></name></wpt>')
    }
    imports = documents.map { |name, body| gpx_import(user, name, body) }
    extract_fixture('malformed_documents', user, imports)
  end

  it 'normalizes three colour shapes and drops one it cannot read' do
    user = create(:user, email: 'w5b-gpx-colours@example.test')
    body = gpx_doc(
      wpt(lat: 51.3397, lon: 12.3731, name: 'Three', type: 'Food', color: '#0fc'),
      wpt(lat: 51.34, lon: 12.38, name: 'Six', type: 'Food', color: '#10c0f0'),
      wpt(lat: 51.35, lon: 12.39, name: 'Eight', type: 'Food', color: '#ffeecc22'),
      wpt(lat: 51.36, lon: 12.40, name: 'Unreadable', type: 'Food', color: 'chartreuse')
    )
    import = gpx_import(user, 'w5b-colours.gpx', body)
    extract_fixture('colour_normalization', user, [import])
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
    extract_fixture('coordinate_edge_cases', user, [import])
  end

  it 'proves the decimal-cast divergence on a waypoint at the probe latitude' do
    user = create(:user, email: 'w5b-gpx-decimal-cast@example.test')
    probe = Float('51.33971249996')
    column_type = Place.type_for_attribute('latitude')
    expect(BigDecimal(probe, 10).round(6)).not_to eq(column_type.cast(probe))
    import = gpx_import(user, 'w5b-decimal-cast.gpx', gpx_doc(wpt(lat: '51.33971249996', lon: '12.3731',
                                                                  name: 'Decimal Cast Probe')))
    writer_fixture('decimal_cast_waypoint', user, import,
                   'decimal_cast' => { 'parsed_lat' => probe,
                                       'bigdecimal_round6' => BigDecimal(probe, 10).round(6).to_s('F'),
                                       'column_cast' => column_type.cast(probe).to_s('F') })
  end

  it 'folds a repeated waypoint, renames a pin within 1 m, and reuses a same-name place within 75 m' do
    user = create(:user, email: 'w5b-gpx-writer-dedup@example.test')
    create(:place, user:, name: 'Old Pin Name', latitude: 51.3397, longitude: 12.3731, source: :gpx_waypoint)
    create(:place, user:, name: 'Shared Name', latitude: 51.3500, longitude: 12.3800, source: :manual)
    body = gpx_doc(
      wpt(lat: 51.3402, lon: 12.3735, name: 'Repeat Me'),
      wpt(lat: 51.3402, lon: 12.3735, name: 'Repeat Me'),
      wpt(lat: 51.3397, lon: 12.3731, name: 'Renamed Pin'),
      wpt(lat: 51.35003, lon: 12.38004, name: 'Shared Name')
    )
    import = gpx_import(user, 'w5b-writer-dedup.gpx', body)
    writer_fixture('writer_dedup', user, import)
  end

  it 'reuses an existing tag by case-insensitive name and skips attaching a privacy-zone tag' do
    user = create(:user, email: 'w5b-gpx-tags@example.test')
    create(:tag, user:, name: 'Cafe', color: '#112233', icon: '📍')
    create(:tag, user:, name: 'Home Zone', color: '#334455', icon: '📍', privacy_radius_meters: 100)
    body = gpx_doc(
      wpt(lat: 51.3397, lon: 12.3731, name: 'Case Insensitive Tag', type: 'CAFE'),
      wpt(lat: 51.35, lon: 12.39, name: 'Privacy Zone Place', type: 'Home Zone'),
      wpt(lat: 51.36, lon: 12.40, name: 'New Tag Place', type: 'Museum', color: '#abc')
    )
    import = gpx_import(user, 'w5b-tags.gpx', body)
    writer_fixture('tag_reuse_and_privacy', user, import)
  end

  it 'truncates a name over 255 characters instead of raising' do
    user = create(:user, email: 'w5b-gpx-long-name@example.test')
    import = gpx_import(user, 'w5b-long-name.gpx', gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'B' * 300)))
    writer_fixture('name_over_limit', user, import)
  end

  it 'extracts a zipped single entry whose first archive member is a directory' do
    user = create(:user, email: 'w5b-gpx-zip@example.test')
    bytes = zip_bytes([['waypoints/', nil], ['favourites.gpx', gpx_doc(wpt(lat: 51.3397, lon: 12.3731,
                                                                           name: 'Zipped Place'))]])
    writer_fixture('zipped_single_entry', user, gpx_import(user, 'w5b-zip.gpx', bytes, content_type: 'application/zip'))
  end

  it 'skips the download when raw_data records zero waypoints seen' do
    user = create(:user, email: 'w5b-gpx-zero-waypoints@example.test')
    import = gpx_import(user, 'w5b-zero-waypoints.gpx', gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Not Extracted')),
                        raw_data: { 'waypoints_seen' => 0, 'trackpoints_seen' => 9 })
    writer_fixture('waypoints_seen_zero', user, import)
  end

  def source_file_case(name, import)
    Imports::SecureFileDownloader.new(import.file).download_to_temp_file.then { |path| File.delete(path) }
    { 'name' => name, 'raised' => nil }
  rescue StandardError => e
    { 'name' => name, 'raised' => e.class.name, 'message' => e.message }
  end

  it "raises Rails' verification messages for a truncated, a mismatched, an empty and a missing file" do
    user = create(:user, email: 'w5b-gpx-source-file@example.test')
    body = gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Verified'))
    truncated = gpx_import(user, 'w5b-truncated.gpx', body)
    truncated.file.blob.update_columns(byte_size: body.bytesize + 10)
    mismatched = gpx_import(user, 'w5b-checksum.gpx', body)
    mismatched.file.blob.update_columns(checksum: Base64.strict_encode64(Digest::MD5.digest('w5b-other-bytes')))
    empty = gpx_import(user, 'w5b-empty.gpx', '')
    missing = create(:import, user:, name: 'w5b-missing.gpx', source: :gpx)
    imports = [truncated, mismatched, empty]
    cases = [source_file_case('truncated', truncated), source_file_case('checksum_mismatch', mismatched),
             source_file_case('zero_byte', empty), source_file_case('no_attachment', missing)]
    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => (imports + [missing]).map { |i| import_row(i) } },
      'files' => imports.map { |import| file_row(import.reload) }, 'expected' => { 'cases' => cases }
    }
    write_fixture('enhanced_import', 'source_file_messages', fixture)
  end

  def zip_case(name, import)
    { 'name' => name, 'import_id' => import.id, 'items' => extracted_items(import) }
  rescue StandardError => e
    { 'name' => name, 'import_id' => import.id, 'raised' => e.class.name, 'message' => e.message }
  end

  it 'unwraps a single-entry zip, refusing an oversized entry and passing an unsafe entry name through' do
    user = create(:user, email: 'w5b-gpx-zip-safety@example.test')
    body = gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Zip Safety'))
    oversized = gpx_import(user, 'w5b-oversized.gpx', zip_bytes([['big.gpx', body]]), content_type: 'application/zip')
    unsafe = gpx_import(user, 'w5b-unsafe.gpx', zip_bytes([['../x.gpx', body]]), content_type: 'application/zip')
    unsafe_case = zip_case('unsafe_entry_name', unsafe)
    stub_const('Archive::Unzipper::MAX_EXTRACTED_SIZE', 10)
    cases = [zip_case('entry_over_max_extracted_size', oversized), unsafe_case]
    fixture = {
      'input' => { 'users' => [user_row(user)], 'imports' => [oversized, unsafe].map { |i| import_row(i) } },
      'files' => [oversized, unsafe].map { |import| file_row(import) },
      'zip_max_extracted_size' => Archive::Unzipper::MAX_EXTRACTED_SIZE, 'expected' => { 'cases' => cases }
    }
    write_fixture('enhanced_import', 'zip_safety', fixture)
  end

  it 'undoes an extraction, removing unreferenced places with their joins but keeping a visited place' do
    user = create(:user, email: 'w5b-gpx-undo@example.test')
    import = gpx_import(user, 'w5b-undo.gpx', gpx_doc(wpt(lat: 51.3397, lon: 12.3731, name: 'Kept By Visit'),
                                                      wpt(lat: 51.35, lon: 12.38, name: 'Removed On Undo')))
    files = [file_row(import)]
    EnhancedImport::ExtractJob.perform_now(import.id)
    kept = Place.find_by!(user_id: user.id, name: 'Kept By Visit')
    removed = Place.find_by!(user_id: user.id, name: 'Removed On Undo')
    create(:visit, user:, area: nil, place: kept, status: :confirmed, name: 'Kept By Visit', duration: 60,
                   started_at: Time.zone.at(base_ts), ended_at: Time.zone.at(base_ts + 3600))
    joined = create(:visit, user:, area: nil, place: nil, status: :confirmed, name: 'Joined Visit', duration: 60,
                            started_at: Time.zone.at(base_ts + 7200), ended_at: Time.zone.at(base_ts + 10_800))
    PlaceVisit.create!(place: removed, visit: joined)
    Tagging.create!(tag: create(:tag, user:, name: 'Undo Tag', color: '#445566', icon: '📍'), taggable: removed)
    Note.create!(user:, attachable: removed, body: 'Undo note', noted_at: Time.zone.at(base_ts))
    effects['kinds'].clear
    effects['card_statuses'].clear
    input = { 'users' => [user_row(user)], 'imports' => [import_row(import.reload)], 'visits' => visit_rows(user),
              'place_visits' => place_visit_rows(user), 'notes' => note_rows(user) }.merge(writer_snapshot(user))
    EnhancedImport::DestroyJob.perform_now(import.id)
    expected = { 'import' => import_row(import.reload), 'visits' => visit_rows(user),
                 'place_visits' => place_visit_rows(user), 'notes' => note_rows(user), 'effects' => effects }
    fixture = { 'input' => input, 'files' => files, 'expected' => expected.merge(writer_snapshot(user)) }
    write_fixture('enhanced_import', 'undo_keeps_visited_place', fixture)
  end
end
