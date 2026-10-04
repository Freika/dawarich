# frozen_string_literal: true

require 'zip'

module NormalImportFormatsSupport
  module_function

  def whole_create_cases
    csv = "latitude,longitude,timestamp\n51.3,12.4,1768519800\n51.3001,12.4001,1768519801\n"
    kml = kml_document(kml_placemark('12.4,51.3,12.75'))
    second_kml = kml_document(kml_placemark('12.5,51.4,1.5'))
    kmz = zip_bytes([['first.KML', kml], ['last.kml', second_kml], ['readme.txt', 'metadata']])
    manifest = { format_version: 2, dawarich_version: '1.9.1', exported_at: '2026-01-15',
                 counts: {}, files: {} }.to_json
    photos = { title: 'synthetic.jpg', imageViews: '0', creationTime: { timestamp: '1768519800' },
               photoTakenTime: { timestamp: '1768519800' },
               geoData: { latitude: 51.3, longitude: 12.4, altitude: 1.5 } }.to_json
    known_zip = zip_bytes([['unmatched.csv', csv],
                           ['Takeout/Location History/Records.json', '{"locations":[]}'],
                           ['Takeout/Google Photos/synthetic.jpg.json', photos]])
    duplicate_zip = zip_bytes([['a/same.csv', csv], ['b/same.csv', csv], ['other.csv', csv]])
    quota_zip = zip_bytes([['first.csv', csv], ['second.csv', csv]])
    cases = [
      { name: 'csv_detected', filename: 'detected.csv', bytes: csv, expected_source: 'csv' },
      { name: 'csv_known', filename: 'known.csv', bytes: csv, source: 'csv', expected_source: 'csv' },
      { name: 'csv_duplicate', filename: 'duplicate.csv', bytes: csv, source: 'csv', duplicate: true,
        expected_source: 'csv' },
      { name: 'csv_all_skipped', filename: 'empty.csv', bytes: "latitude,longitude,timestamp\n", source: 'csv',
        expected_source: 'csv' },
      { name: 'csv_single_zip', filename: 'wrapped.zip', bytes: zip_bytes([['nested/points.csv', csv]]),
        expected_source: 'csv' },
      { name: 'kmz_plain', filename: 'plain.kmz', bytes: kmz, source: 'kml', expected_source: nil },
      { name: 'kmz_wrapped', filename: 'client.zip', bytes: zip_bytes([['plain.kmz', kmz]]), source: 'kml',
        expected_source: 'kml', leaf: kmz },
      { name: 'kmz_missing_leaf', filename: 'client.zip', bytes: zip_bytes([['plain.kmz',
                                                                             zip_bytes([['readme.txt', 'metadata']])]]),
        source: 'kml', expected_source: 'kml' },
      { name: 'fit_failed_return', filename: 'broken.fit', bytes: 'not a FIT file', source: 'fit',
        expected_source: 'fit' },
      { name: 'v2_profile', filename: 'profile.zip', bytes: zip_bytes([['manifest.json', manifest]]),
        expected_source: 'user_data_archive' },
      { name: 'v1_profile', filename: 'profile.zip', bytes: zip_bytes([['data.json',
                                                                        '{"counts":{},"settings":{},"points":[]}']]),
        expected_source: 'user_data_archive' },
      { name: 'invalid_manifest', filename: 'manifest.zip',
        bytes: zip_bytes([['manifest.json', '{"format_version":3}']]),
        expected_source: nil },
      { name: 'unsupported_single', filename: 'readme.zip', bytes: zip_bytes([['readme.txt', 'metadata']]),
        expected_source: nil },
      { name: 'zip_known_preference', filename: 'takeout.zip', bytes: known_zip, expected_source: nil },
      { name: 'zip_duplicate_names', filename: 'duplicates.zip', bytes: duplicate_zip,
        expected_source: nil, existing_child: 'other.csv (from duplicates.zip)' },
      { name: 'zip_later_child_failure', filename: 'limited.zip', bytes: quota_zip,
        source: 'csv', trial: true, expected_source: 'csv' }
    ]
    cases << cases.last.merge(name: 'zip_extractor_later_child_failure', direct: true)
    large_manifest = JSON.parse(manifest).merge('padding' => 'x' * 1_048_577).to_json
    large_v1 = "{\"counts\":{},\"settings\":{},\"points\":[#{'0,' * 40_000}0]}"
    late_v1 = "#{' ' * 65_536}{\"counts\":{},\"settings\":{}}"
    [
      ['v2_large', [['manifest.json', large_manifest]], nil],
      ['v1_large', [['data.json', large_v1]], 'user_data_archive'],
      ['v1_late_prefix', [['data.json', late_v1]], nil],
      ['nested_profile', [['nested/data.json', '{"counts":{},"settings":{}}']], nil],
      ['directory_single', [['nested/', ''], ['nested/points.csv', csv]], 'csv']
    ].each do |name, entries, expected_source|
      cases << { name:, filename: "#{name}.zip", bytes: zip_bytes(entries), expected_source: }
    end
    [
      ['mobile_photo_library', 'points', mobile_photo_library_cases, 'mobile_import_valid'],
      ['google_records', 'locations', google_records_cases, 'records_import_legacy'],
      ['google_semantic_history', 'timelineObjects', google_semantic_cases, 'semantic_import_legacy'],
      ['polarsteps', 'locations', polarsteps_cases, 'polarsteps_import_legacy']
    ].each do |source, section, inputs, input_name|
      original = inputs.find { |row| row.first == input_name }[1]
      ['[]', JSON.parse(original).fetch(section).to_json].each_with_index do |last, index|
        first = index.zero? ? original : original.sub(/"#{section}":\[.*\]/m, %Q("#{section}":[]))
        bytes = "#{first.delete_suffix('}')},#{section.to_json}:#{last}}"
        cases << { name: "duplicate_section_#{source}_#{index}", filename: "#{source}.json",
                   bytes:, source:, expected_source: source }
      end
    end
    [true, 'invalid', {}, { invalid: true }, nil, []].each_with_index do |locations, index|
      cases << { name: "records_shape_#{index}", filename: 'Records.json',
                 bytes: { locations: }.to_json, source: 'google_records', expected_source: 'google_records' }
    end
    cases << { name: 'records_shape_missing', filename: 'Records.json', bytes: '{}',
               source: 'google_records', expected_source: 'google_records' }
    [
      ['zip_unsafe_skip', [['../ignored.csv', csv], ['safe.csv', csv]], 'unsafe.zip'],
      ['zip_dotfiles', [['.hidden.csv', csv], ['.hidden/points.csv', csv], ['readme.txt', 'text']], 'hidden.zip'],
      ['zip_supported_source', [['safe.csv', csv], ['readme.txt', 'text']], 'archive.csv']
    ].each do |name, entries, filename|
      cases << { name:, filename:, bytes: zip_bytes(entries), expected_source: nil }
    end
    duplicate_entries = zip_bytes([['one.csv', csv], ['two.csv', csv.sub('51.3', '51.4')]])
    cases << { name: 'zip_duplicate_entries', filename: 'duplicates.zip',
               bytes: duplicate_entries.gsub('two.csv', 'one.csv'), expected_source: 'csv' }
    cases << { name: 'zip_path_skip', filename: 'skip.zip',
               bytes: zip_bytes([['ignored..csv', csv], ['safe.csv', csv]]), expected_source: nil }
    cases << { name: 'bounded_tcx_nodes', filename: 'nodes.tcx',
               bytes: tcx_document(tcx_activity(tcx_point('2026-01-15T23:30:00Z', '<x/>' * 1025))),
               source: 'tcx', expected_source: 'tcx' }
    cases << { name: 'bounded_csv_line', filename: 'oversized.csv',
               bytes: "latitude,longitude,timestamp,ignored\n51.3,12.4,1768519800,#{'x' * 1_048_577}\n",
               source: 'csv', expected_source: 'csv' }
    rec = { _type: 'location', lat: 51.3, lon: 12.4, tst: 1_768_519_800, padding: 'x' * 1_048_577 }
    cases << { name: 'bounded_rec_line', filename: 'oversized.rec',
               bytes: "2026-01-15T23:30:00Z\t*\t#{rec.to_json}\n",
               source: 'owntracks', expected_source: 'owntracks' }
    cases << { name: 'empty_zip', filename: 'empty.zip', bytes: zip_bytes([]), expected_source: nil }
    cases << { name: 'malformed_zip', filename: 'broken.zip', bytes: "PK#{[3, 4].pack('C*')}broken",
               expected_source: nil }
    %w[en de].each do |locale|
      cases << { name: "unknown_#{locale}", filename: 'unknown.txt', bytes: 'no known source', locale:,
                 expected_source: nil }
    end
    cases
  end

  def zip_bytes(entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, bytes|
        zip.put_next_entry(name)
        zip.write(bytes)
      end
    end
    buffer.string
  end

  def capture_whole_create(options)
    FileUtils.mkdir_p(DIR.join('whole_create'))
    zone = options.fetch(:zone, 'Europe/Berlin')
    locale = options.fetch(:locale, 'de')
    cleanup_create_claims
    sequences = reset_create_sequences
    blobs = []
    result = nil
    Time.use_zone(zone) do
      I18n.with_locale(locale) do
        user, import = owner!(zone, locale)
        import.update_columns(name: options.fetch(:filename), source: Import.sources[options[:source]])
        import.skip_background_processing = true
        import.file.attach(io: StringIO.new(options.fetch(:bytes)), filename: options.fetch(:filename))
        blobs << import.file.blob
        if options[:trial]
          user.update_columns(status: User.statuses[:trial])
          3.times { |i| user.imports.create!(name: "existing-#{i}.csv", skip_background_processing: true) }
        end
        if options[:existing_child]
          user.imports.create!(name: options[:existing_child], skip_background_processing: true)
        end
        initial_imports = user.imports.where.not(id: import.id).order(:id).map { |row| whole_import_row(row) }
        initial_points = []
        if options[:duplicate]
          Csv::Importer.new(import, user.id, write_whole_input(options)).call
          initial_points = snapshot(import).fetch('points')
          import.points.update_all(import_id: nil)
          import.update_columns(raw_points: 0, doubles: 0, processed: 0)
        end
        input = write_whole_input(options)
        archive = capture_archive(input)
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        effects = []
        allow_json_effects(effects)
        before_source = import.reload.source
        if options[:direct]
          Imports::ZipExtractor.new(import, user.id, input).call
        else
          Imports::Create.new(user, import).call
        end
      rescue StandardError => e
        failure = { 'class' => e.class.name, 'message' => e.message }
      ensure
        parent = Import.find_by(id: 987_101)
        rows = Import.where(user_id: 987_001).where.not(id: 987_101).order(:id)
        children = rows.map { |child| whole_import_row(child) }
        points = parent ? snapshot(parent) : { 'points' => [], 'sources' => [] }
        blobs += ActiveStorage::Attachment.where(record_type: 'Import', record_id: [987_101] + rows.pluck(:id))
                                          .includes(:blob).map(&:blob)
        result = { 'zone' => zone, 'locale' => locale, 'input' => File.basename(input),
                   'identities' => { 'user_id' => 987_001, 'import_id' => 987_101 },
                   'initial_source' => before_source, 'source_transition' => parent&.source,
                   'initial_points' => initial_points, 'initial_imports' => initial_imports,
                   'trial' => options[:trial] == true,
                   'parent' => parent && whole_import_row(parent), 'children' => children,
                   'points' => points['points'], 'sources' => points['sources'],
                   'notifications' => Notification.where(user_id: 987_001).order(:id).pluck(:title, :content, :kind),
                   'jobs' => ActiveJob::Base.queue_adapter.enqueued_jobs.map do |job|
                     { 'type' => job[:job].name, 'args' => job[:args] }
                   end, 'commands' => effects, 'archive' => archive, 'error' => failure }
        if options[:leaf]
          Zip::File.open_buffer(options[:leaf]) do |zip|
            selected = zip.find { |entry| entry.name.downcase.end_with?('.kml') }
            result['kmz_leaf'] = { 'name' => selected.name, 'bytes' => byte_value(selected.get_input_stream.read) }
          end
        end
      end
    end
    result
  ensure
    cleanup_whole_create(blobs || [])
    restore_create_sequences(sequences) if sequences
  end

  def write_whole_input(options)
    path = DIR.join('whole_create', "#{options.fetch(:name)}.input#{File.extname(options.fetch(:filename))}")
    File.binwrite(path, options.fetch(:bytes))
    path.to_s
  end

  def whole_import_row(import)
    row = import.attributes.slice('id', 'name', *IMPORT_COLUMNS, 'additional_data_extraction_status',
                                  'additional_data_extraction', 'processing_started_at')
    row['file'] = if import.file.attached?
                    { 'filename' => import.file.filename.to_s, 'content_type' => import.file.content_type,
                      'bytes' => byte_value(import.file.download) }
                  end
    row
  end

  def capture_archive(input)
    dispatch = Archive::Unzipper.inspect_archive(input)
    result = { 'kind' => dispatch.kind.to_s, 'entry_name' => dispatch.entry_name }
    if dispatch.kind == :single_entry
      extracted = Archive::Unzipper.extract_single(input)
      result['bytes'] = byte_value(File.binread(extracted))
      File.unlink(extracted)
    end
    result
  end

  def byte_value(bytes) = { '__bytes__' => bytes.unpack1('H*') }

  def reset_create_sequences
    connection = ActiveRecord::Base.connection
    %w[imports active_storage_blobs].to_h do |table|
      sequence = connection.select_value("SELECT pg_get_serial_sequence('#{table}','id')")
      state = connection.select_one("SELECT last_value,is_called FROM #{sequence}")
      connection.execute("SELECT setval('#{sequence}',#{table == 'imports' ? 987_201 : 987_301},false)")
      [sequence, state]
    end
  end

  def restore_create_sequences(sequences)
    sequences.each do |sequence, state|
      ActiveRecord::Base.connection.execute("SELECT setval('#{sequence}',#{state['last_value']},#{state['is_called']})")
    end
  end

  def cleanup_create_claims
    PhoenixClaims.unclaim(Achievements::CheckJob.lock_key(987_001))
    _, token = Achievements::PendingChecks.read(987_001)
    Achievements::PendingChecks.consume(987_001, token)
  end

  def cleanup_whole_create(blobs)
    cleanup_create_claims
    blobs.each { |blob| blob.service.delete(blob.key) }
    ids = blobs.map(&:id).uniq
    ActiveStorage::Attachment.where(blob_id: ids).delete_all
    ActiveStorage::Blob.where(id: ids).delete_all
    connection = ActiveRecord::Base.connection
    %w[points notifications imports users].each do |table|
      key = table == 'users' ? 'id' : 'user_id'
      connection.execute("DELETE FROM #{table} WHERE #{key}=987001")
    end
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
end
