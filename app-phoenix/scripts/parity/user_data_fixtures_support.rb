# frozen_string_literal: true

require 'zip'
require_relative 'a12b_fixture_support'

module UserDataFixturesSupport
  DIR = Rails.root.join('app-phoenix/test/fixtures/user_data')
  SECTIONS = %w[settings areas imports exports trips notifications places tags taggings points visits stats tracks
                digests raw_data_archives].freeze
  MONTHLY = %w[points visits stats tracks digests].freeze
  USER_IDS = (988_001..988_009)
  MODELS = { 'areas' => Area, 'places' => Place, 'imports' => Import, 'exports' => Export, 'trips' => Trip,
             'notifications' => Notification, 'tags' => Tag, 'points' => Point, 'visits' => Visit,
             'stats' => Stat, 'tracks' => Track, 'digests' => Users::Digest,
             'raw_data_archives' => Points::RawDataArchive }.freeze

  module_function

  def write(name, data)
    FileUtils.mkdir_p(DIR)
    DIR.join(name).binwrite("#{JSON.pretty_generate(data)}\n")
  end

  def with_users
    yield
  ensure
    clean_users
  end

  def clean_users
    tracks = Track.where(user_id: USER_IDS).pluck(:id)
    tags = Tag.where(user_id: USER_IDS).pluck(:id)
    Tagging.where(tag_id: tags).delete_all
    TrackSegment.where(track_id: tracks).delete_all
    attachments = MODELS.values.flat_map do |model|
      ActiveStorage::Attachment.where(record_type: model.polymorphic_name,
                                      record_id: model.where(user_id: USER_IDS).select(:id)).to_a
    end
    attachments.each do |attachment|
      blob = attachment.blob
      attachment.delete
      blob.purge
    end
    %w[points visits tracks trips imports exports areas notifications places tags stats digests
       raw_data_archives].each do |name|
      MODELS.fetch(name).where(user_id: USER_IDS).delete_all
    end
    User.unscoped.where(id: USER_IDS).delete_all
    Country.where(id: 988_991).delete_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def owner(id = 988_001, zone = 'UTC')
    User.insert_all!([{ id: id, email: "user-data-#{id}@example.invalid", created_at: Time.current,
                        updated_at: Time.current, settings: { 'timezone' => zone, 'locale' => 'en',
                                                             'gps_filtering_enabled' => false, 'retained' => 'yes' } }])
    User.find(id)
  end

  def insert(model, user, id, attributes)
    model.insert_all!([{ id: id, user_id: user.id, created_at: Time.current, updated_at: Time.current, **attributes }])
    model.find(id)
  end

  def attach(record, bytes, filename, content_type)
    record.file.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
  end

  def corpus
    JSON.parse(Rails.root.join('app-phoenix/test/fixtures/a12b/crypto.json').read)['archives']['written'].first
  end

  def raw_gzip = Base64.strict_decode64(corpus.fetch('gzip'))

  def with_crypto
    previous = ENV.fetch('ARCHIVE_ENCRYPTION_KEY', nil)
    ENV.delete('ARCHIVE_ENCRYPTION_KEY')
    Points::RawData::Encryption.reset!
    yield
  ensure
    previous.nil? ? ENV.delete('ARCHIVE_ENCRYPTION_KEY') : (ENV['ARCHIVE_ENCRYPTION_KEY'] = previous)
    Points::RawData::Encryption.reset!
  end

  def dataset(zone)
    user = owner(988_001, zone)
    foreign = owner(988_002)
    Country.insert_all!([{ id: 988_991, name: 'Synthetic Republic', iso_a2: 'ZZ', iso_a3: 'ZZZ',
                           geom: 'MULTIPOLYGON(((12 51,13 51,13 52,12 51)))',
                           created_at: Time.current, updated_at: Time.current }])
    insert(Place, foreign, 988_502, name: 'Synthetic <home>&', latitude: 51.3, longitude: 12.4,
                                      lonlat: 'POINT(12.4 51.3)')
    insert(Area, user, 988_601, name: 'Synthetic area', latitude: 51.3, longitude: 12.4, radius: 100)
    place = insert(Place, user, 988_501, name: 'Synthetic <home>&', latitude: 51.3, longitude: 12.4,
                                         lonlat: 'POINT(12.4 51.3)', geodata: { 'nullable' => nil, 'flag' => false })
    import = insert(Import, user, 988_101, name: 'synthetic.json', source: 1, status: 1,
                                          additional_data_extraction_status: 1, processed: false)
    attach(import, '{"note":"synthetic & < >"}', 'synthetic &.json', 'application/json')
    export = insert(Export, user, 988_201, name: 'synthetic export', file_format: 0, status: 1)
    attach(export, '{"points":[]}', 'synthetic.json', 'application/json')
    insert(Trip, user, 988_301, name: 'Synthetic trip', started_at: Time.utc(2026, 1, 31, 23, 30),
                              ended_at: Time.utc(2026, 2, 1, 1), distance: 1250)
    insert(Notification, user, 988_401, title: 'Synthetic <title>&', content: 'café 😀', kind: 0, read_at: nil)
    tag = insert(Tag, user, 988_701, name: 'Synthetic tag', icon: nil, color: '#123456')
    Tagging.create!(id: 988_711, tag: tag, taggable: place)
    visit = insert(Visit, user, 988_801, name: 'Synthetic visit', place_id: place.id,
                                      started_at: Time.utc(2026, 1, 31, 23, 30), ended_at: Time.utc(2026, 2, 1),
                                      duration: 1800, status: 1)
    [Time.utc(2026, 1, 31, 23, 30), Time.utc(2026, 2, 1, 0, 30),
     Time.utc(2026, 3, 1, 0, 30)].each_with_index do |time, i|
      insert(Point, user, 988_901 + i, timestamp: time.to_i, lonlat: 'POINT(12.4 51.3)', altitude: 12,
                                     altitude_decimal: 12.75, accuracy: 10, tracker_id: 'synthetic',
                                     import_id: import.id,
                                     visit_id: visit.id, raw_data: { 'nullable' => nil, 'flag' => false },
                                     country_id: 988_991, country: 'Synthetic Republic',
                                     inrids: ['home'], in_regions: [], velocity: 1.25)
    end
    user.update_columns(points_count: 3)
    insert(Stat, user, 988_951, year: 2026, month: 1, distance: 1250, daily_distance: [[31, 1.25]],
                                 sharing_uuid: '00000000-0000-4000-8000-000000988951')
    track = insert(Track, user, 988_961, start_at: Time.utc(2026, 1, 31, 23, 30), end_at: Time.utc(2026, 2, 1),
                                        original_path: 'LINESTRING(12.4 51.3,12.5 51.4)', distance: 1250,
                                        avg_speed: 2.5, duration: 1800, dominant_mode: 1)
    TrackSegment.create!(id: 988_962, track: track, transportation_mode: :walking, start_index: 0, end_index: 1,
                         distance: 1250, duration: 1800)
    insert(Users::Digest, user, 988_971, year: 2026, month: 1, period_type: 0, distance: 1250,
                                       monthly_distances: { '31' => 1250 },
                                       sharing_uuid: '00000000-0000-4000-8000-000000988971')
    raw = insert(Points::RawDataArchive, user, 988_981, year: 2026, month: 1, chunk_number: 1, point_count: 3,
                                                     point_ids_checksum: 'synthetic-checksum',
                                                     archived_at: Time.current,
                                                     metadata: {
                                                       'format_version' => 2, 'encryption' => 'aes-256-gcm',
                                                       'compression' => 'gzip', 'content_checksum' => 'synthetic',
                                                       'expected_count' => 3, 'actual_count' => 3
                                                     })
    attach(raw, corpus.fetch('message'), 'synthetic.jsonl.gz.enc', 'application/octet-stream')
    Export.connection.reset_pk_sequence!('exports')
    user
  end

  def extracted(export)
    Tempfile.create(['user-data-oracle', '.zip']) do |file|
      file.binmode
      file.write(export.file.download)
      file.flush
      Zip::File.open(file.path) do |zip|
        zip.each_with_object({}) do |entry, rows|
          next if entry.directory?
          raise 'Backup entry is not deflated' unless entry.compression_method == Zip::Entry::DEFLATED

          rows[entry.name] = entry.get_input_stream.read
        end
      end
    end
  end

  def save_entries(name, entries)
    unsafe = {}
    entries.each do |path, bytes|
      if path.start_with?('/', '\\') || path.split('/').include?('..')
        unsafe[path] = Base64.strict_encode64(bytes)
        next
      end
      target = DIR.join(name, 'entries', path)
      FileUtils.mkdir_p(target.dirname)
      target.binwrite(bytes)
    end
    write("#{name}/unsafe_entries.json", unsafe) unless unsafe.empty?
  end

  def archive(entries)
    Tempfile.create(['user-data-oracle', '.zip']) do |file|
      file.close
      FileUtils.rm_f(file.path)
      Zip::File.open(file.path, create: true) do |zip|
        entries.each do |name, bytes|
          safe = name.gsub(/\A[\x2f\\]+/) { |prefix| '_' * prefix.bytesize }
          zip.get_output_stream(safe) { |out| out.write(bytes) }
        end
      end
      bytes = File.binread(file.path)
      entries.each_key do |name|
        safe = name.gsub(/\A[\x2f\\]+/) { |prefix| '_' * prefix.bytesize }
        bytes = bytes.gsub(safe, name) unless safe == name
      end
      File.binwrite(file.path, bytes)
      yield file.path
    ensure
      FileUtils.rm_f(file.path)
    end
  end

  def result
    { 'result' => JSON.parse(JSON.generate(yield)), 'error' => nil }
  rescue StandardError => e
    { 'result' => nil, 'error' => { 'class' => e.class.name, 'message' => e.message } }
  end

  def notifications(user)
    user.notifications.order(:id).as_json(except: %w[id user_id])
  end

  def jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.map do |job|
      { 'class' => job[:job].name, 'args' => job[:args], 'queue' => job[:queue] }
    end
  end

  def snapshot(user)
    ids = MODELS.transform_values { |model| model.where(user_id: user.id).order(:id).pluck(:id) }
    rows = MODELS.transform_values do |model|
      model.where(user_id: user.id).order(:id).map do |record|
        attributes = record.as_json(except: %w[id user_id])
        attributes.each do |key, value|
          next unless value && key.end_with?('_id')

          table = key.delete_suffix('_id').pluralize
          attributes[key] = ids[table]&.index(value)&.+(1) if ids.key?(table)
        end
        attributes['sharing_uuid'] = 'generated' if attributes['sharing_uuid']
        attributes['lonlat'] = record.lonlat&.as_text if record.respond_to?(:lonlat)
        attributes['original_path'] = record.original_path&.as_text if record.respond_to?(:original_path)
        attributes['path'] = record.path&.as_text if record.respond_to?(:path)
        attributes['source_id'] = record.source&.digest if record.is_a?(Point)
        attributes['file'] = attachment_snapshot(record) if record.respond_to?(:file) && record.file.attached?
        attributes
      end
    end
    rows['taggings'] = Tagging.where(tag_id: ids['tags']).order(:id).map do |tagging|
      { 'tag' => tagging.tag.name, 'type' => tagging.taggable_type, 'name' => tagging.taggable&.name }
    end
    rows['segments'] = TrackSegment.where(track_id: ids['tracks']).order(:id).as_json(except: %w[id track_id])
    { 'rows' => rows, 'settings' => user.reload.settings, 'points_count' => user.points_count }
  end

  def attachment_snapshot(record)
    content = result { Base64.strict_encode64(record.file.download) }
    { 'filename' => record.file.filename.to_s, 'content_type' => record.file.content_type,
      'bytes' => content['result'], 'error' => content['error'] }
  end

  def restore(name, entries, user, save: true, detailed: true)
    save_entries(name, entries) if save
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    outcome = archive(entries) { |path| result { Users::ImportData.new(user, path).import } }
    rows = detailed ? snapshot(user) : { 'settings' => user.reload.settings, 'points_count' => user.points_count }
    outcome.merge(rows, 'notifications' => notifications(user), 'jobs' => jobs)
  end

  def portable
    with_users do
      with_crypto do
        entries = extracted(Users::ExportData.new(dataset('UTC')).export)
        row = JSON.parse(entries.fetch('raw_data_archives.jsonl').lines.first)
        { 'bytes' => Base64.strict_encode64(entries.fetch("files/#{row.fetch('file_name')}")),
          'metadata' => row.fetch('metadata'), 'file_name' => row.fetch('file_name') }
      end
    end
  end

  def failure(name, entries: nil)
    with_users do
      entries ||= name == 'missing' ? { 'unrelated.txt' => 'synthetic' } : { 'manifest.json' => '{"format_version":3}' }
      save_entries(name, entries)
      service_user = owner
      service = restore(name, entries, service_user)
      job_user = owner(988_003)
      insert(Point, job_user, 988_904, timestamp: Time.current.to_i, lonlat: 'POINT(12.4 51.3)')
      job_user.update_columns(points_count: 91)
      import = insert(Import, job_user, 988_102, name: 'synthetic restore', source: 8, status: 1)
      archive(entries) { |path| attach(import, File.binread(path), 'synthetic.zip', 'application/zip') }
      outcome = result { Users::ImportDataJob.new.perform(import.id) }
      job = outcome.merge('status' => import.reload.status, 'error_message' => import.error_message,
                          'points_count' => job_user.reload.points_count, 'notifications' => notifications(job_user))
      { 'service' => service, 'job' => job }
    end
  end
end

require_relative 'user_data_fixtures_cases'
