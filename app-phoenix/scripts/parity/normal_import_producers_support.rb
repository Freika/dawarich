# frozen_string_literal: true

require 'tmpdir'

module NormalImportFormatsSupport
  module_function

  def producer_observer
    Object.new.extend(RSpec::Mocks::ExampleMethods).extend(WebMock::API)
  end

  def capture_producers
    { 'immich' => capture_photo_producer('immich'), 'photoprism' => capture_photo_producer('photoprism'),
      'watcher' => capture_watcher_producer, 'stale' => capture_stale_producer,
      'teslamate' => capture_teslamate_producer, 'trek' => capture_trek_producer }
  end

  def capture_producer(settings = {})
    sequences = reset_create_sequences(%w[imports active_storage_blobs trips])
    observer = producer_observer
    observer.allow(DawarichSettings).to observer.receive(:self_hosted?).and_return(true)
    cleanup_create_claims
    Tracks::RealtimeDebouncer.new(987_001).clear
    user, initial = owner!('Europe/Berlin', 'de')
    initial.delete
    before_blobs = ActiveStorage::Blob.pluck(:id)
    user.update_columns(settings: user.settings.merge(settings))
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    requests = []
    result = nil
    error = nil
    begin
      result = yield(user, requests, observer)
    rescue StandardError => e
      error = { 'class' => e.class.name, 'message' => e.message }
    end
    imports = user.imports.order(:id).map { |row| whole_import_row(row) }
    columns = POINT_COLUMNS.map do |column|
      column == 'lonlat' ? 'ST_AsText(lonlat::geometry) AS lonlat' : ActiveRecord::Base.connection.quote_column_name(column)
    end
    points = ActiveRecord::Base.connection.select_all(
      "SELECT #{columns.join(',')} FROM points WHERE user_id=987001 ORDER BY timestamp,id"
    ).to_a
    points.each do |point|
      %w[raw_data motion_data].each { |key| point[key] = JSON.parse(point[key]) if point[key].is_a?(String) }
      %w[altitude_decimal course course_accuracy].each { |key| point[key] = point[key]&.to_s }
    end
    { 'identities' => { 'user_id' => user.id }, 'zone' => Time.zone.name, 'locale' => 'de',
      'requests' => requests, 'result' => result, 'error' => error, 'imports' => imports, 'points' => points,
      'blobs' => ActiveStorage::Blob.where.not(id: before_blobs).order(:id).map do |blob|
        { 'id' => blob.id, 'filename' => blob.filename.to_s, 'content_type' => blob.content_type,
          'bytes' => byte_value(blob.download) }
      end,
      'settings' => user.reload.settings.select do |key, _|
        key.start_with?('teslamate_last_', 'teslamate_processing_')
      end,
      'notifications' => user.notifications.order(:id).pluck(:title, :content, :kind),
      'jobs' => ActiveJob::Base.queue_adapter.enqueued_jobs.map do |job|
        { 'type' => job[:job].name, 'args' => job[:args] }
      end }
  ensure
    blobs = before_blobs ? ActiveStorage::Blob.where.not(id: before_blobs).to_a : []
    user&.trip_sources&.each { |source| source.trips.destroy_all }
    TripSource.where(user_id: 987_001).delete_all
    Export.where(user_id: 987_001).delete_all
    cleanup_whole_create(blobs || [])
    Tracks::RealtimeDebouncer.new(987_001).clear
    restore_create_sequences(sequences) if sequences
    WebMock.reset!
  end

  def capture_photo_producer(provider)
    service = provider == 'immich' ? Immich::ImportGeodata : Photoprism::ImportGeodata
    job = provider == 'immich' ? Import::ImmichGeodataJob : Import::PhotoprismGeodataJob
    url = "http://127.0.0.1:19991/#{provider}"
    settings = { "#{provider}_url" => url, "#{provider}_api_key" => 'synthetic-provider-fixture' }
    %w[success duplicate empty invalid transport auth quota].to_h do |name|
      value = capture_producer(settings) do |user, requests, observer|
        asset = if provider == 'immich'
                  { 'fileCreatedAt' => '2026-01-15T23:30:00Z',
                    'exifInfo' => { 'latitude' => 51.3, 'longitude' => 12.4 } }
                else
                  { 'Lat' => 51.3, 'Lng' => 12.4, 'TakenAt' => '2026-01-15T23:30:00Z' }
                end
        method = provider == 'immich' ? :post : :get
        endpoint = provider == 'immich' ? "#{url}/api/search/metadata" : "#{url}/api/v1/photos"
        request = observer.stub_request(method, /#{Regexp.escape(endpoint)}/)
        if name == 'transport'
          request.to_raise(Net::ReadTimeout.new('synthetic provider timeout'))
        else
          page = 0
          request.to_return do |req|
            page += 1
            parameters = method == :post ? JSON.parse(req.body) : CGI.parse(req.uri.query.to_s)
            items = name == 'empty' || page.even? ? [] : [asset]
            items = [{ 'invalid' => true }] if name == 'invalid' && page.odd?
            body = provider == 'immich' ? { 'assets' => { 'items' => items } }.to_json : items.to_json
            requests << { 'method' => method.to_s, 'parameters' => parameters, 'status' => name == 'auth' ? 401 : 200,
                          'body' => body }
            { status: name == 'auth' ? 401 : 200, body:, headers: { 'content-type' => 'application/json' } }
          end
        end
        if name == 'quota'
          user.update_columns(status: User.statuses.fetch('trial'))
          5.times { |index| user.imports.create!(name: "existing-#{index}.csv", skip_background_processing: true) }
          ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        end
        if name == 'transport'
          job.new.perform(user.id)
        else
          service.new(user).call
          service.new(user).call if name == 'duplicate'
          nil
        end
      end
      [name, value]
    end
  end

  def capture_watcher_producer
    %w[success duplicate cloud formats].to_h do |name|
      value = capture_producer do |user, requests, observer|
        Dir.mktmpdir('a7-watcher-') do |root|
          observer.stub_const('Imports::Watcher::WATCHED_DIR_PATH', Pathname.new(root))
          FileUtils.mkdir_p(File.join(root, user.email))
          FileUtils.mkdir_p(File.join(root, 'foreign@example.invalid'))
          bytes = "latitude,longitude,timestamp\n51.3,12.4,1768519800\n"
          File.binwrite(File.join(root, user.email, 'synthetic.csv'), bytes)
          File.binwrite(File.join(root, 'foreign@example.invalid', 'foreign.csv'), bytes)
          File.binwrite(File.join(root, user.email, 'ignored.txt'), 'unsupported')
          if name == 'formats'
            { 'synthetic.gpx' => '<gpx/>', 'Records.json' => '{"locations":[]}', 'synthetic.rec' => 'record',
              'synthetic.tcx' => '<TrainingCenterDatabase/>', 'synthetic.fit' => 'FIT',
              'synthetic.geojson' => '{"type":"FeatureCollection","features":[]}', 'synthetic.kml' => '<kml/>',
              'synthetic.kmz' => zip_bytes([['first.kml', '<kml/>']]),
              'synthetic.zip' => zip_bytes([['first.csv', bytes], ['second.csv', bytes]]) }.each do |file, content|
              File.binwrite(File.join(root, user.email, file), content)
              requests << { 'file' => file, 'bytes' => byte_value(content) }
            end
          end
          requests << { 'files' => { 'synthetic.csv' => byte_value(bytes), 'foreign.csv' => byte_value(bytes),
                                    'ignored.txt' => byte_value('unsupported') } }
          observer.allow(DawarichSettings).to observer.receive(:self_hosted?).and_return(name != 'cloud')
          Import::WatcherJob.new.perform
          Import::WatcherJob.new.perform if name == 'duplicate'
          { 'files_remain' => File.binread(File.join(root, user.email, 'synthetic.csv')) == bytes }
        end
      end
      [name, value]
    end
  end

  def capture_stale_producer
    %w[success monitor_failure].to_h do |name|
      value = capture_producer do |user, _requests, observer|
        import = user.imports.create!(name: 'stale.csv', source: :csv, status: :processing,
                                      skip_background_processing: true)
        import.update_column(:processing_started_at, 7.hours.ago)
        export = Export.create!(id: 987_601, user:, name: 'stale.json', status: :processing)
        export.update_column(:processing_started_at, 3.hours.ago)
        user.imports.create!(name: 'recent.csv', source: :csv, status: :processing, skip_background_processing: true)
        if name == 'monitor_failure'
          observer.allow_any_instance_of(Imports::ExtractionMonitor)
                  .to observer.receive(:call).and_raise('monitor failed')
        end
        begin
          StaleJobsRecoveryJob.new.perform
        rescue StandardError => e
          failure = { 'class' => e.class.name, 'message' => e.message }
        end
        { 'exports' => user.exports.order(:id).map do |row|
          row.attributes.slice('id', 'name', 'status', 'error_message')
        end,
          'monitor_error' => failure }
      end
      [name, value]
    end
  end
end
