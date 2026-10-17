# frozen_string_literal: true

module UserDataFixturesSupport
  module_function

  def capture
    exports = %w[UTC Europe/Berlin America/New_York].index_with do |zone|
      Time.use_zone(zone) { with_users { with_crypto { capture_export(zone) } } }
    end
    entries = read_entries('export_UTC')
    restores = with_users { capture_restores(entries) }
    boundaries = [4999, 5000, 5001].map { |count| with_users { capture_boundary(count) } }
    cases = edge_cases(entries).to_h do |name, input|
      [name, with_users { restore(name, input, owner) }]
    end
    errors = %w[missing_attachment tampered_archive].index_with do |name|
      with_users { with_crypto { capture_export_failure(name) } }
    end
    { 'sections' => SECTIONS, 'versions' => [1, 2], 'exports' => exports, 'restores' => restores,
      'boundaries' => boundaries, 'cases' => cases, 'export_errors' => errors }
  end

  def capture_export(zone)
    user = dataset(zone)
    initial = seed_rows(user)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    export = Users::ExportData.new(user).export
    entries = extracted(export)
    name = "export_#{zone.tr('/', '_')}"
    save_entries(name, entries)
    manifest = JSON.parse(entries.fetch('manifest.json'))
    listing = entries.sort.map { |path, bytes| { 'name' => path, 'size' => bytes.bytesize, 'compression' => 8 } }
    { 'manifest' => manifest, 'listing' => listing,
      'status' => export.status, 'notifications' => notifications(user), 'jobs' => jobs, 'seed_rows' => initial,
      'zone' => zone, 'locale' => 'en' }
  end

  def seed_rows(user)
    rows = MODELS.to_h do |name, model|
      data = model.where(user_id: [user.id, 988_002]).order(:id).map do |record|
        attributes = record.attributes.transform_values do |value|
          value.respond_to?(:as_text) ? value.as_text : value
        end
        record.class.defined_enums.each_key do |column|
          attributes[column] = record.public_send("#{column}_before_type_cast")
        end
        attributes
      end
      [name, data]
    end
    rows['storage'] = MODELS.values.flat_map do |model|
      model.where(user_id: user.id).filter_map do |record|
        next unless record.respond_to?(:file) && record.file.attached?

        { 'record_type' => record.class.polymorphic_name, 'record_id' => record.id,
          'filename' => record.file.filename.to_s, 'content_type' => record.file.content_type,
          'bytes' => Base64.strict_encode64(record.file.download) }
      end
    end
    rows['users'] = User.where(id: [user.id, 988_002]).order(:id).map do |record|
      { 'id' => record.id, 'email' => record.email, 'settings' => record.settings,
        'points_count' => record.points_count, 'created_at' => Time.current, 'updated_at' => Time.current }
    end
    rows['countries'] = Country.where(id: 988_991).map do |record|
      record.attributes.merge('geom' => record.geom.as_text)
    end
    rows['taggings'] = Tagging.where(tag_id: user.tags.select(:id)).map(&:attributes)
    rows['track_segments'] = TrackSegment.where(track_id: user.tracks.select(:id)).map do |record|
      record.attributes.merge('transportation_mode' => record.transportation_mode_before_type_cast,
                              'confidence' => record.confidence_before_type_cast)
    end
    rows
  end

  def read_entries(name)
    directory = DIR.join(name, 'entries')
    Dir.glob(directory.join('**/*')).reject { |path| File.directory?(path) }.to_h do |path|
      [Pathname.new(path).relative_path_from(directory).to_s, File.binread(path)]
    end
  end

  def envelope(entries)
    manifest = JSON.parse(entries.fetch('manifest.json'))
    SECTIONS.to_h do |section|
      filenames = MONTHLY.include?(section) ? manifest['files'][section] : ["#{section}.jsonl"]
      rows = filenames.flat_map { |path| entries.fetch(path).lines.map { |line| JSON.parse(line) } }
      [section, section == 'settings' ? rows.first : rows]
    end.merge('counts' => manifest.fetch('counts'))
  end

  def v1_entries(entries, reversed: false)
    data = envelope(entries)
    data = data.to_a.reverse.to_h if reversed
    entries.select { |path, _| path.start_with?('files/') }.merge('data.json' => data.to_json)
  end

  def root_entries(entries)
    data = envelope(entries)
    manifest = JSON.parse(entries.fetch('manifest.json')).merge('files' => {})
    roots = data.except('counts').to_h do |name, rows|
      records = name == 'settings' ? [rows] : rows
      ["#{name}.jsonl", "#{records.map(&:to_json).join("\n")}\n"]
    end
    entries.select do |path, _|
      path.start_with?('files/')
    end.merge(roots, 'manifest.json' => JSON.pretty_generate(manifest))
  end

  def capture_restores(entries)
    foreign = dataset('UTC')
    user = owner(988_003)
    before = snapshot(foreign)
    output = { 'v2' => restore('v2', entries, user), 'v2_repeat' => restore('v2_repeat', entries, user),
               'v1' => restore('v1', v1_entries(entries), owner(988_004)),
               'v1_reversed' => restore('v1_reversed', v1_entries(entries, reversed: true), owner(988_005)),
               'v2_root' => restore('v2_root', root_entries(entries), owner(988_006)) }
    raise 'Foreign rows changed during restore' unless snapshot(foreign) == before

    output
  end

  def capture_boundary(count)
    rows = count.times.map do |i|
      time = Time.utc(2026, 1, 1) + i * 60
      { 'name' => "Synthetic #{i}", 'latitude' => 51.3, 'longitude' => 12.4,
        'started_at' => time.iso8601, 'ended_at' => (time + 30).iso8601, 'duration' => 30,
        'status' => 'confirmed', 'timestamp' => time.to_i }
    end
    places = rows.map { |row| row.slice('name', 'latitude', 'longitude') }
    visits = rows.map { |row| row.slice('name', 'started_at', 'ended_at', 'duration', 'status') }
    points = rows.map { |row| row.slice('latitude', 'longitude', 'timestamp') }
    entries = { 'manifest.json' => '{"format_version":2,"files":{}}' }
    { 'places' => places, 'visits' => visits, 'points' => points }.each do |name, records|
      entries["#{name}.jsonl"] = "#{records.map(&:to_json).join("\n")}\n"
    end
    user = owner
    outcome = restore("boundary_#{count}", entries, user, detailed: false)
    outcome.merge('count' => count, 'counts' => { 'points' => user.points.count, 'places' => user.places.count,
                                               'visits' => user.visits.count })
  end

  def capture_export_failure(name)
    user = dataset('UTC')
    record = name == 'missing_attachment' ? user.imports.first : user.raw_data_archives.first
    blob = record.file.blob
    if name == 'missing_attachment'
      blob.service.delete(blob.key)
    else
      blob.service.upload(blob.key, StringIO.new('synthetic tampered ciphertext'))
    end
    export = Users::ExportData.new(user).export
    entries = extracted(export)
    save_entries(name, entries)
    { 'status' => export.status, 'entries' => entries.keys.sort,
      'imports' => entries.fetch('imports.jsonl').lines.map { |line| JSON.parse(line) },
      'raw_data_archives' => entries.fetch('raw_data_archives.jsonl').lines.map { |line| JSON.parse(line) } }
  end

  def edge_cases(entries)
    roots = root_entries(entries)
    manifest = JSON.parse(entries.fetch('manifest.json'))
    reversed = manifest.deep_dup
    reversed['files'].transform_values!(&:reverse)
    missing_files = entries.reject { |path, _| path.start_with?('files/') }
    invalid_rows = roots.merge('areas.jsonl' => "\nnull\n{}\n{\"name\":\"invalid\"}\n",
                               'notifications.jsonl' => "null\n{}\n{\"title\":\"invalid\"}\n")
    paths = { 'manifest.json' => { 'format_version' => 2, 'files' => {
      'points' => ['../outside.jsonl', '/tmp/synthetic.jsonl', 'missing.jsonl', 'points/ok.jsonl']
    } }.to_json, '/settings.jsonl' => '{"timezone":"Europe/Berlin","gps_filtering_enabled":false}',
              'points/ok.jsonl' => "{\"timestamp\":1767225600,\"lonlat\":\"POINT(12.4 51.3)\"}\n",
              '../outside.jsonl' => 'invalid', 'files/../unwanted' => 'invalid' }
    dropped = { 'manifest.json' => '{"format_version":2}', 'points.jsonl' => {
      'timestamp' => 1_767_225_600, 'lonlat' => 'POINT(12.4 51.3)', 'removed_column' => 'old',
      'altitude' => 12, 'inrids' => '{home}', 'raw_data' => '{"flag":false}', 'user_id' => 988_002
    }.to_json }
    {
      'v2_sorted' => entries.merge('manifest.json' => reversed.to_json),
      'missing_files' => missing_files,
      'invalid_entities' => invalid_rows,
      'unsafe_paths' => paths,
      'dropped_columns' => dropped,
      'invalid_manifest' => { 'manifest.json' => '{]', 'data.json' => '{}' },
      'invalid_jsonl_root' => { 'manifest.json' => '{"format_version":2}', 'areas.jsonl' => "\n{]\n" },
      'invalid_jsonl_monthly' => { 'manifest.json' => '{"format_version":2,"files":{"points":["points/bad.jsonl"]}}',
                                   'points/bad.jsonl' => "\n{]\n" },
      'manifest_precedence' => { 'manifest.json' => '{"format_version":3}', 'data.json' => '{}' },
      'manifest_string_version' => { 'manifest.json' => '{"format_version":"2"}' },
      'transaction_error' => { 'manifest.json' => '{"format_version":2}',
                               'settings.jsonl' => '{"timezone":"Europe/Berlin"}',
                               'tags.jsonl' => '{"name":"synthetic","nonexistent_column":true}' },
      'recoverable_exports' => { 'manifest.json' => '{"format_version":2}',
                                 'exports.jsonl' => { 'name' => 'bad', 'status' => 'completed', 'file_format' => 'json',
                                                      'old_column' => true }.to_json },
      'recoverable_raw_file_error' => { 'manifest.json' => '{"format_version":2}',
                                       'raw_data_archives.jsonl' => {
                                         'year' => 2026, 'month' => 1, 'chunk_number' => 1,
                                         'file_error' => 'missing synthetic file'
                                       }.to_json }
    }
  end
end
