# frozen_string_literal: true

require 'rails_helper'
require_relative 'normal_import_formats_support'
require_relative 'normal_import_release_support'
require_relative 'normal_import_json_support'
require_relative 'normal_import_photos_support'
require_relative 'normal_import_records_support'
require_relative 'normal_import_semantic_support'
require_relative 'normal_import_phone_support'
require_relative 'normal_import_kml_support'
require_relative 'normal_import_create_support'
require_relative 'normal_import_producers_support'
require_relative 'normal_import_sync_producers_support'
require_relative 'normal_import_tcx_support'
require_relative 'normal_import_fit_support'
require_relative '../../../spec/support/fit_fixture_helper'

RSpec.describe 'Phoenix fixtures: normal Rails import formats' do
  before do
    @previous_urls = Rails.application.routes.default_url_options.dup
    Rails.application.routes.default_url_options = @previous_urls.merge(host: 'www.example.com')
  end

  after { Rails.application.routes.default_url_options = @previous_urls }

  include ActiveSupport::Testing::TimeHelpers
  include NormalImportReleaseSupport
  self.use_transactional_tests = false

  after(:all) do
    captured = NormalImportFormatsSupport.closure_cases.sort.to_h
    selected = captured.select { |name, _| %w[source_detection dispatch].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f01', selected) unless selected.empty?
    selected = captured.select { |name, _| %w[csv atomic].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f02', selected) unless selected.empty?
    selected = captured.select { |name, _| ['geojson'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f03', selected) unless selected.empty?
    selected = captured.select { |name, _| ['owntracks'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f04', selected) unless selected.empty?
    selected = captured.select { |name, _| ['gpx'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f05', selected) unless selected.empty?
    selected = captured.select { |name, _| ['kml'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f06', selected) unless selected.empty?
    selected = captured.select { |name, _| ['tcx'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f07', selected) unless selected.empty?
    selected = captured.select { |name, _| ['fit'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f08', selected) unless selected.empty?
    selected = captured.select { |name, _| ['polarsteps'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f09', selected) unless selected.empty?
    selected = captured.select { |name, _| ['mobile'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f10', selected) unless selected.empty?
    selected = captured.select { |name, _| ['records'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f11', selected) unless selected.empty?
    selected = captured.select { |name, _| ['semantic'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f12', selected) unless selected.empty?
    selected = captured.select { |name, _| ['phone'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f13', selected) unless selected.empty?
    selected = captured.select { |name, _| ['whole_create'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f14', selected) unless selected.empty?
    selected = captured.select { |name, _| ['resume/gpx'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f15', selected) unless selected.empty?
    selected = captured.select { |name, _| ['resume/normal'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f16', selected) unless selected.empty?
    selected = captured.select { |name, _| ['continuation'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f17', selected) unless selected.empty?
    selected = captured.select { |name, _| ['extraction'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f18', selected) unless selected.empty?
    selected = captured.select { |name, _| ['postprocess', 'whole_create/post'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f19', selected) unless selected.empty?
    selected = captured.select { |name, _| ['google_photos'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f20', selected) unless selected.empty?
    selected = captured.select { |name, _| ['photos'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f21', selected) unless selected.empty?
    selected = captured.select { |name, _| ['whole_create/kmz'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f22', selected) unless selected.empty?
    selected = captured.select { |name, _| ['enhanced/23'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f23', selected) unless selected.empty?
    selected = captured.select { |name, _| ['enhanced/24'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f24', selected) unless selected.empty?
    selected = captured.select { |name, _| ['enhanced/25'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f25', selected) unless selected.empty?
    selected = captured.select { |name, _| ['enhanced/26'].any? { name.start_with?(_1) } }
    NormalImportFormatsSupport.write('a12f3a-f26', selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/watcher/') }
                       .transform_keys { _1.delete_prefix('producers/watcher/') }
    capture_producer_alias(7, selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/immich/') }
                       .transform_keys { _1.delete_prefix('producers/immich/') }
    capture_producer_alias(8, selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/teslamate/') }
                       .transform_keys { _1.delete_prefix('producers/teslamate/') }
    capture_producer_alias(9, selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/stale/') }
                       .transform_keys { _1.delete_prefix('producers/stale/') }
    capture_producer_alias(10, selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/photoprism/') }
                       .transform_keys { _1.delete_prefix('producers/photoprism/') }
    capture_producer_alias(11, selected) unless selected.empty?
    selected = captured.select { |name, _| name.start_with?('producers/trek/') }
                       .transform_keys { _1.delete_prefix('producers/trek/') }
    capture_producer_alias(12, selected) unless selected.empty?
  end

  def capture_producer_alias(task, selected)
    path = Rails.root.join("app-phoenix/test/fixtures/imports_pages/a12f3a-i#{task.to_s.rjust(2, '0')}.json")
    order = JSON.parse(path.read).keys
    selected = producer_alias_plain(selected.sort_by { |name, _| order.index(name) || order.length }.to_h)
    FixtureRecording.verify(path, "#{JSON.pretty_generate(selected)}\n")
  end

  def producer_alias_plain(value)
    case value
    when Hash then value.transform_values { producer_alias_plain(_1) }
    when Array then value.map { producer_alias_plain(_1) }
    when Time, DateTime, ActiveSupport::TimeWithZone then value.as_json
    else value
    end
  end

  def extracted_plain(value)
    case value
    when Hash then value.transform_values { extracted_plain(_1) }
    when Array then value.map { extracted_plain(_1) }
    when Time, DateTime then value.iso8601(6)
    when Struct, Data then extracted_plain(value.to_h)
    else value
    end
  end

  def capture_dispatch
    ActiveRecord::Base.transaction(requires_new: true) do
      user, import = NormalImportFormatsSupport.owner!('UTC')
      creator = Imports::Create.new(user, import)
      values = (Import.sources.keys + [nil, 'zip', 'unsupported']).to_h do |source|
        result = error = nil
        begin
          result = creator.send(:importer, source).name
        rescue ArgumentError => e
          error = { class: e.class.name, message: e.message }
        end
        [source.to_s, { source:, result:, error: }]
      end
      expect(values.fetch('gpx')[:result]).to eq('Gpx::TrackImporter')
      expect(values.fetch('zip')[:error]).to include(class: 'ArgumentError')
      NormalImportFormatsSupport.write('dispatch', values)
      raise ActiveRecord::Rollback
    end
  end

  def capture_enhanced_adapters
    duration = { startTimestamp: '2026-01-15T10:00:00Z', endTimestamp: '2026-01-15T11:00:00Z' }
    location = { latitudeE7: 513_000_000, longitudeE7: 124_000_000, placeId: 'synthetic', name: 'Café' }
    semantic = { timelineObjects: [{ placeVisit: { location:, duration:, visitConfidence: 0.8 } },
                                   { activitySegment: { duration:, activityType: 'WALKING', distance: 1000,
                                                        confidence: 0.9 } }] }.to_json
    phone = { semanticSegments: [{ startTime: duration[:startTimestamp], endTime: duration[:endTimestamp],
              visit: { topCandidate: { placeId: 'synthetic', probability: 0.8, semanticType: 'HOME',
                                      placeLocation: { latLng: '51.3°, 12.4°' } } },
              activity: { distanceMeters: 1000, topCandidate: { type: 'WALKING', probability: 0.9 } } }],
              userLocationProfile: { frequentPlaces: [{ placeId: 'home', label: 'Home',
                                                       placeLocation: '51.3,12.4' }] } }.to_json
    polarsteps = [{ id: 1, location: { lat: 51.3, lon: 12.4 }, display_name: 'Café',
                   arrived: 1_768_471_200, departed: 1_768_474_800 }].to_json
    adapters = [
      [23, EnhancedImport::Adapters::GoogleSemanticHistoryAdapter,
       NormalImportFormatsSupport.google_semantic_cases + [['enhanced_valid', semantic, 'UTC']]],
      [24, EnhancedImport::Adapters::GooglePhoneTakeoutAdapter,
       NormalImportFormatsSupport.google_phone_cases + [['enhanced_valid', phone, 'UTC']]],
      [25, EnhancedImport::Adapters::GoogleRecordsAdapter, NormalImportFormatsSupport.google_records_cases],
      [26, EnhancedImport::Adapters::PolarstepsAdapter,
       NormalImportFormatsSupport.polarsteps_cases + [['enhanced_valid', polarsteps, 'UTC']]]
    ]
    adapters.each do |task, adapter, cases|
      cases.each do |name, bytes, zone|
        Time.use_zone(zone) do
          ActiveRecord::Base.transaction(requires_new: true) do
            _, import = NormalImportFormatsSupport.owner!(zone)
            rows = []
            error = nil
            Dir.mktmpdir('a12f3a-adapter') do |directory|
              path = File.join(directory, 'input.json')
              File.binwrite(path, bytes)
              begin
                adapter.new(import, path).translate { rows << extracted_plain(_1.to_h) }
              rescue StandardError => e
                error = { class: e.class.name, message: FixtureRecording.normalize(e.message) }
              end
            end
            expect(rows).not_to be_empty if name == 'enhanced_valid'
            expect(rows).to be_empty if task == 25
            NormalImportFormatsSupport.write("enhanced/#{task}/#{name}",
                                             { zone:, input: NormalImportFormatsSupport.byte_value(bytes), rows:,
error: })
            raise ActiveRecord::Rollback
          end
        end
      end
    end
  end

  def capture_postprocessing
    input = "latitude,longitude,timestamp\n51.3,12.4,1768519800\n"
    %w[success filter_anomalies schedule_stats_creating schedule_visit_suggesting
       schedule_track_generation].each do |name|
      RSpec::Mocks.with_temporary_scope do
        unless name == 'success'
          allow_any_instance_of(Imports::Create).to receive(name.to_sym)
            .and_raise(StandardError, "synthetic post-processing #{name} failure")
        end
        options = { name: "postprocess_#{name}", filename: 'postprocess.csv', bytes: input,
                    source: 'csv', expected_source: 'csv', locale: 'en' }
        result = NormalImportFormatsSupport.capture_whole_create(options)
        expect(result['parent']['status']).to eq('completed')
        expect(result['points'].size).to eq(1)
        if name != 'success'
          expect(result['notifications'].count { _1.first == 'Import post-processing incomplete' }).to eq(1)
        end
        NormalImportFormatsSupport.write("postprocess/#{name}", result)
      end
    end
  end

  def capture_gpx_tracks
    point = '<trkpt lat="51.3" lon="12.4"><time>2026-01-15T23:30:00Z</time><ele>12.75</ele></trkpt>'
    cases = { 'valid' => "<gpx><trk><trkseg>#{point}</trkseg></trk></gpx>", 'empty' => '<gpx/>',
              'malformed' => '<gpx><trk><trkseg><trkpt',
                'duplicates' => "<gpx><trk><trkseg>#{point * 2}</trkseg></trk></gpx>",
              'legacy' => "<gpx><trk><trkseg>#{point}</trkseg></trk></gpx>" }
    cases.each do |name, bytes|
      result = NormalImportFormatsSupport.capture_json("gpx_tracks_#{name}", bytes, 'UTC', 4, Gpx::TrackImporter)
      expect(result['points'].size).to eq(1) if name == 'valid'
      NormalImportFormatsSupport.write("gpx_tracks_#{name}", result)
    end
  end

  def capture_resume_lineage
    phoenix_tables!
    phoenix_leases!
    PhoenixSchema.reset!
    %w[gpx normal].each do |lane|
      service = lane == 'gpx' ? Imports::GpxResume : Imports::NormalResume
      type = "imports.process_#{lane}"
      %w[process repeat no_receipt wrong_user wrong_zone completed deleting deleted_user forward fallback
         busy].each_with_index do |name, index|
        user, import = NormalImportFormatsSupport.owner!('Pacific/Auckland')
        import.update_columns(source: Import.sources.fetch(lane == 'gpx' ? 'gpx' : 'csv'))
        bytes = if lane == 'gpx'
                  '<gpx><trk><trkseg><trkpt lat="51" lon="13"><time>2026-01-01T10:00:00</time>' \
                    '</trkpt></trkseg></trk></gpx>'
                else
                  "latitude,longitude,timestamp\n51,13,2026-01-01 10:00:00\n"
                end
        import.file.attach(io: StringIO.new(bytes), filename: "resume.#{lane == 'gpx' ? 'gpx' : 'csv'}")
        event = "00000000-0000-4000-8000-#{format('%012d', index + (lane == 'gpx' ? 100 : 200))}"
        payload = { 'event_id' => event, 'import_id' => import.id, 'user_id' => user.id,
'time_zone' => 'Pacific/Auckland' }
        job_owner!("command:#{type}", %w[forward fallback].include?(name) ? :oban : :sidekiq)
        query = 'INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone,native_fallback) ' \
                  'VALUES (?,?,?,?,?)'
        unless name == 'no_receipt'
          ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(
                                                  [query, event, import.id, user.id, payload['time_zone'],
                                                   name == 'fallback']
                                                ))
        end
        import.update_columns(status: Import.statuses.fetch(name)) if %w[completed deleting].include?(name)
        user.update_columns(deleted_at: Time.current) if name == 'deleted_user'
        request = payload.dup
        request['user_id'] += 1 if name == 'wrong_user'
        request['time_zone'] = 'UTC' if name == 'wrong_zone'
        clear_enqueued_jobs
        error = nil
        RSpec::Mocks.with_temporary_scope do
          allow(SecureRandom).to receive(:uuid).and_return('00000000-0000-4000-8000-000000000999')
          begin
            if name == 'busy'
              hold_import_lock("import:#{import.id}") { service.perform(request) }
            else
              service.perform(request)
              service.perform(request) if %w[repeat forward].include?(name)
            end
          rescue StandardError => e
            error = { class: e.class.name, message: FixtureRecording.normalize(e.message) }
          end
        end
        statement = 'SELECT event_id,import_id,user_id,time_zone,state,forwarded_event_id,native_fallback ' \
                    'FROM phoenix.import_handoffs WHERE event_id=?'
        receipt = ActiveRecord::Base.connection.select_one(
          ActiveRecord::Base.sanitize_sql_array([statement, event])
        )
        expect(import.reload.points.count).to eq(%w[process repeat fallback].include?(name) ? 1 : 0)
        expect(receipt['state']).to eq('forwarded') if name == 'forward'
        expect(error[:class]).to eq(service::Busy.name) if name == 'busy'
        NormalImportFormatsSupport.write("resume/#{lane}/#{name}", { payload:, request:, receipt:, error:,
          import: NormalImportFormatsSupport.snapshot(import),
          outbox: JobOutbox.where(aggregate_id: 987_101, command_type: type).order(:event_id).map do
            _1.attributes.slice('event_id', 'command_type', 'payload', 'dedupe_key')
          end,
          jobs: enqueued_jobs.map { { class: _1[:job].name, args: _1[:args], queue: _1[:queue] } } })
      ensure
        blobs = ActiveStorage::Blob.joins(:attachments)
                                   .where(active_storage_attachments: { record_type: 'Import',
record_id: 987_101 }).to_a
        NormalImportFormatsSupport.cleanup_whole_create(blobs)
        connection = ActiveRecord::Base.connection
        %w[import_handoffs import_runs].each do |table|
          connection.execute("DELETE FROM phoenix.#{table} WHERE import_id=987101")
        end
        JobOutbox.where(aggregate_id: 987_101, command_type: type).delete_all
        connection.execute(ActiveRecord::Base.sanitize_sql_array(['DELETE FROM phoenix.job_owners WHERE key=?',
                                                                  "command:#{type}"]))
      end
    end
  end

  def capture_google_continuation
    %w[valid malformed unsupported_row].each do |name|
      ActiveRecord::Base.transaction(requires_new: true) do
        _, import = NormalImportFormatsSupport.owner!('UTC')
        input = [{ latitudeE7: 513_000_000, longitudeE7: 124_000_000, timestamp: '2026-01-15T23:30:00Z',
                   deviceTag: 'synthetic' }].to_json
        input = '{' if name == 'malformed'
        input = '[null]' if name == 'unsupported_row'
        error = nil
        begin
          Import::GoogleTakeoutJob.perform_now(import.id, input, 1000)
        rescue StandardError => e
          error = { class: e.class.name, message: FixtureRecording.normalize(e.message) }
        end
        expect(import.points.count).to eq(name == 'valid' ? 1 : 0)
        NormalImportFormatsSupport.write("continuation/#{name}", { input:, current_index: 1000,
          result: NormalImportFormatsSupport.snapshot(import), error:,
          retry: Import::GoogleTakeoutJob.get_sidekiq_options['retry'] })
        raise ActiveRecord::Rollback
      end
    end
  end

  it 'A12rel import parent records file backfill and track effects' do
    corpus = capture_release_imports
    cases = corpus.fetch('cases').index_by { _1.fetch('id') }
    expect(corpus.fetch('retry').fetch('max_attempts')).to eq(26)
    %w[missing deleted unsupported nil_source shape_error sql_failure phone_sql_failure].each do |name|
      expect(cases.fetch(name).fetch('track_calls')).to eq([])
    end
    %w[google_records owntracks geojson absent download_error malformed checksum size empty].each do |name|
      expect(cases.fetch(name).fetch('track_calls')).to eq([987_101])
      expect(cases.fetch(name).fetch('error')).to be_nil
    end
    %w[google_records owntracks geojson].each do |name|
      expect(cases.fetch(name).fetch('downloads')).to eq(0)
    end
    semantic = cases.fetch('semantic').fetch('after').fetch('points')
    expect(semantic.find { _1.fetch('id') == 56_303 }.fetch('motion_data'))
      .to include('retained' => 'point', 'activityType' => 'CYCLING')
    %w[phone_object phone_array].each do |name|
      expect(cases.fetch(name).fetch('update_order')).to eq([56_304, 56_301, 56_303])
      point = cases.fetch(name).fetch('after').fetch('points').find { _1.fetch('id') == 56_304 }
      expect(point.fetch('motion_data').fetch('activityRecord')).to include('extra' => 'exact_first')
    end
    failure = cases.fetch('sql_failure')
    expect(failure.fetch('error').fetch('class')).to eq('ActiveRecord::StatementInvalid')
    expect(failure.fetch('observed')).to eq(failure.fetch('after'))
    expect(failure.fetch('after')).not_to eq(failure.fetch('before'))
    expect(failure.fetch('retry').fetch('error')).to be_nil
    phone_failure = cases.fetch('phone_sql_failure')
    expect(phone_failure.fetch('error').fetch('class')).to eq('ActiveRecord::StatementInvalid')
    expect(phone_failure.fetch('update_order')).to eq([56_304])
    expect(phone_failure.fetch('observed')).to eq(phone_failure.fetch('before'))
    expect(phone_failure.fetch('after')).to eq(phone_failure.fetch('before'))
    expect(phone_failure.fetch('retry').fetch('error')).to be_nil
    expect(phone_failure.fetch('retry').fetch('after')).to eq(cases.fetch('phone_object').fetch('after'))
    expect(phone_failure.fetch('retry').fetch('track_calls')).to eq([987_101])
    expect(capture_release_imports).to eq(corpus)
    record_import_release_fixture('imports', corpus)
  end

  it 'A12rel import batch preserves segments and continues after a broken track' do
    corpus = capture_release_track_batches
    cases = corpus.fetch('cases').index_by { _1.fetch('id') }
    batch = cases.fetch('sql_failure')
    expect(batch.fetch('attempted')).to eq(3)
    expect(batch.fetch('reported')).to include(include('class' => 'ActiveRecord::StatementInvalid'))
    expect(batch.fetch('observed')).to eq(batch.fetch('after'))
    expect(batch.fetch('after').fetch('tracks').take(3).map { _1.fetch('dominant_mode') })
      .to eq(%w[unknown driving unknown])
    expect(cases.fetch('unchanged').fetch('broadcasts').size).to eq(3)
    expect(cases.fetch('unchanged').fetch('tile_ranges').size).to eq(3)
    expect(cases.fetch('empty').fetch('after').fetch('tracks').take(3).map { _1.fetch('dominant_mode') })
      .to eq(%w[driving driving driving])
    expect(cases.fetch('nil_user').fetch('detectors').map { _1.fetch('enabled_modes') }.uniq).to eq([nil])
    expect(cases.fetch('selection').fetch('attempted')).to eq(3)
    expect(capture_release_track_batches).to eq(corpus)
    record_import_release_fixture('track_batches', corpus)
  end

  it 'A12rel import migrations record schema-specific selections and delays' do
    corpus = capture_release_import_vectors
    vectors = corpus.fetch('vectors').index_by { _1.fetch('id') }
    expect(vectors.fetch('integer_historical').fetch('jobs')).to eq([])
    expect(vectors.fetch('integer_historical').fetch('reported'))
      .to include(include('uninitialized constant'), include('invalid input syntax for type integer'))
    historical = vectors.fetch('text_historical').fetch('jobs')
                        .select { _1.fetch('class') == 'TransportationModes::ImportBackfillJob' }
    expect(historical.map { _1.fetch('due_offset') }).to eq([180, 190, 200, 210, 220])
    current = vectors.fetch('integer_unreleased').fetch('jobs')
                     .select { _1.fetch('class') == 'TransportationModes::ImportBackfillJob' }
    expect(current.map { _1.fetch('arguments').first }).to eq([987_101, 987_102, 987_103, 987_104, 987_105])
    expect(current.map { _1.fetch('due_offset') }).to eq([120, 130, 140, 150, 160])
    expect(vectors.fetch('integer_unreleased').fetch('jobs').first.fetch('class'))
      .to eq('DataMigrations::BackfillTransportationModesJob')
    expect(vectors.fetch('integer_no_tracks').fetch('jobs').none? do |job|
      job.fetch('class') == 'DataMigrations::BackfillTransportationModesJob'
    end).to be(true)
    expect(capture_release_import_vectors).to eq(corpus)
    record_import_release_fixture('import_release_vectors', corpus)
  end

  it 'records integration producers and scheduler effects' do
    travel_to Time.utc(2026, 1, 15, 23, 30) do
      results = NormalImportFormatsSupport.capture_producers
      results.each do |provider, cases|
        FileUtils.mkdir_p(NormalImportFormatsSupport::DIR.join('producers', provider))
        cases.each { |name, value| NormalImportFormatsSupport.write("producers/#{provider}/#{name}", value) }
      end
      { watcher: 'i07', immich: 'i08', teslamate: 'i09', stale: 'i10', photoprism: 'i11', trek: 'i12' }
        .each do |provider, task|
          path = Rails.root.join("app-phoenix/test/fixtures/imports_pages/a12f3a-#{task}.json")
          data = results.fetch(provider.to_s).as_json
          if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
            File.write(path, "#{JSON.pretty_generate(data)}\n")
          else
            expect(JSON.parse(path.read)).to eq(data.as_json)
          end
        end
      expect(results.keys).to eq(%w[immich photoprism watcher stale teslamate trek])
      %w[immich photoprism].each do |provider|
        expect(results.fetch(provider).fetch('success').fetch('error')).to be_nil
        row = results.fetch(provider).fetch('success').fetch('imports').first
        expect(row.fetch('source')).to eq("#{provider}_api")
        expect(row.fetch('file').fetch('content_type')).to eq('application/json')
        expected_bytes = '[{"latitude":51.3,"longitude":12.4,"lonlat":"SRID=4326;POINT(12.4 51.3)",' \
                         '"timestamp":1768519800}]'
        expect(row.fetch('file').fetch('bytes')).to eq(NormalImportFormatsSupport.byte_value(expected_bytes))
        expect(results.fetch(provider).fetch('duplicate').fetch('notifications').size).to eq(1)
        expect(results.fetch(provider).fetch('empty').fetch('imports')).to eq([])
        expect(results.fetch(provider).fetch('auth').fetch('imports')).to eq([])
        expect(results.fetch(provider).fetch('transport').fetch('error').fetch('class')).to eq('Net::ReadTimeout')
        expect(results.fetch(provider).fetch('quota').fetch('error').fetch('class')).to eq('ActiveRecord::RecordInvalid')
      end
      expect(results.fetch('watcher').fetch('duplicate').fetch('imports').map { |row| row.fetch('name') })
        .to eq(['synthetic.csv'])
      expect(results.fetch('watcher').fetch('cloud').fetch('imports')).to eq([])
      %w[success monitor_failure].each do |name|
        expect(results.fetch('stale').fetch(name).fetch('imports').map { |row| row.fetch('status') })
          .to eq(%w[failed processing])
      end
      point = results.fetch('teslamate').fetch('success').fetch('points').first
      expect(point).to include('lonlat' => 'POINT(12.4 51.3)', 'velocity' => '4.4704', 'battery' => 80)
      expect(results.fetch('teslamate').fetch('duplicate').fetch('points')).to eq([point])
      expect(results.fetch('teslamate').fetch('quota').fetch('points')).to eq([])
      expect(results.fetch('teslamate').fetch('incomplete').fetch('error').fetch('class'))
        .to eq('TeslaMate::Sync::IncompleteError')
      expect(results.fetch('trek').fetch('success').fetch('result').fetch('error')).to be_nil
      expect(results.fetch('trek').fetch('success').fetch('result').fetch('trips').first.fetch('source_status'))
        .to eq('active')
      expect(results.fetch('trek').fetch('stopped').fetch('result').fetch('trips').first.fetch('source_status'))
        .to eq('stopped')
      expect(results.fetch('trek').fetch('unauthorized').fetch('result').fetch('source').fetch('status'))
        .to eq('disabled')
      expect(results.fetch('trek').fetch('disconnected').fetch('requests')).to eq([])
      continuation = results.fetch('trek').fetch('continuation').fetch('jobs')
                            .find { |job| job.fetch('type') == 'Trek::ImportTripsJob' }
      expect(continuation.fetch('args').last).to eq(100)
    end
  end

  it 'records the importer result independently of the native adapter' do
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      Time.use_zone(zone) do
        travel_to Time.utc(2026, 1, 15, 23, 30) do
          result = NormalImportFormatsSupport.capture_csv(zone)
          expect(result.fetch('detector')).to eq('csv')
          expect(result.fetch('import').fetch('doubles')).to eq(1)
          expect(result.fetch('import').fetch('raw_points')).to eq(2)
          expect(result.fetch('points').size).to eq(1)
          expect(result.fetch('points').first.fetch('lonlat')).to eq('POINT(12.4 51.3)')
          expect(result.fetch('notifications')).to eq([])
          expect(result.fetch('error')).to be_nil
          NormalImportFormatsSupport.write("csv_#{zone.tr('/', '_')}", result)
        end
      end
    end
    travel_to Time.utc(2026, 1, 15, 23, 30) do
      [false, true].each do |atomic|
        result = NormalImportFormatsSupport.capture_batch_failure(atomic)
        expect(result.fetch('points').size).to eq(atomic ? 0 : 1000)
        expect(result.fetch('import').fetch('raw_points')).to eq(atomic ? 0 : 1000)
        expect(result.fetch('notifications').size).to eq(atomic ? 0 : 1)
        expect(result.fetch('import').fetch('doubles')).to eq(0)
        name = atomic ? 'atomic_second_batch_failure' : 'csv_second_batch_failure'
        NormalImportFormatsSupport.write(name, result)
      end
    end
    travel_to Time.utc(2026, 1, 15, 23, 30) do
      capture_postprocessing
      capture_gpx_tracks
      capture_enhanced_adapters
      capture_resume_lineage
      capture_google_continuation
      capture_dispatch
    end
    detection = NormalImportFormatsSupport.capture_detection
    detection.each { |row| expect(row.fetch('source')).to eq(row.fetch('expected')) }
    NormalImportFormatsSupport.write('source_detection', detection)
    lexical = NormalImportFormatsSupport.capture_csv_lexical
    expect(lexical.find { |row| row['name'] == 'trailing_nil' }.fetch('fields')).to eq(['a', nil])
    expect(lexical.find { |row| row['name'] == 'quoted_empty' }.fetch('fields')).to eq(['', nil])
    expect(lexical.find { |row| row['name'] == 'unclosed' }.fetch('error').fetch('class'))
      .to eq('CSV::MalformedCSVError')
    NormalImportFormatsSupport.write('csv_lexical', lexical)
  end

  context 'CSV' do
    it 'records CSV importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.csv_import_cases.each do |name, bytes, zone, legacy|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !legacy)
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_csv_case(name, bytes, zone, legacy)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          expect(result.fetch('import').fetch('doubles')).to be_a(Integer)
          NormalImportFormatsSupport.write(name, result.merge('commands' => effects))
        end
      end
    end
  end

  context 'Polarsteps' do
    it 'records Polarsteps importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.polarsteps_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 13, Polarsteps::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Mobile photo library' do
    it 'records mobile photo library importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.mobile_photo_library_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 15, MobilePhotoLibrary::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Photos' do
    it 'records photo importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.photos_cases.each do |name, bytes, source|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          importer = source == 14 ? GooglePhotos::Importer : Photos::Importer
          result = NormalImportFormatsSupport.capture_json(name, bytes, 'UTC', source, importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Google Records' do
    it 'records Google Records preparation and importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_records_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 2, GoogleMaps::RecordsStorageImporter)
          prepared = NormalImportFormatsSupport.capture_records_preparation(bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(prepared).to include('prepared_points', 'device_tags')
          NormalImportFormatsSupport.write(name, result.merge(prepared))
        end
      end
    end
  end

  context 'Google Semantic History' do
    it 'records Google Semantic History importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_semantic_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 0, GoogleMaps::SemanticHistoryImporter)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('import').fetch('raw_points')).to eq(0)
          identities = { 'user_id' => 987_001, 'import_id' => 987_101 }
          NormalImportFormatsSupport.write(name, result.merge('identities' => identities))
        end
      end
    end
  end

  context 'Google Phone preparation' do
    it 'records Google Phone point preparation from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_phone_point_cases.each do |name, section, value, zone, legacy|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !legacy)
          result = NormalImportFormatsSupport.capture_phone_preparation(section, value, zone, legacy)
          expect(result).to include('prepared_points', 'section', 'input', 'error')
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'Google Phone importer' do
    it 'records Google Phone importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.google_phone_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_phone_import(name, bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          commands = result['error'] ? [] : result['commands']
          identities = { 'user_id' => 987_001, 'import_id' => 987_101 }
          NormalImportFormatsSupport.write(name, result.merge('identities' => identities, 'commands' => commands,
                                                              'attempted_commands' => result['commands']))
        end
      end
    end
  end

  context 'KML' do
    it 'records KML importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.kml_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 9, Kml::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'TCX' do
    it 'records TCX importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.tcx_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 11, Tcx::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'motion_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'FIT importer' do
    it 'records FIT hierarchy and importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.fit_import_cases(self).each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          result = NormalImportFormatsSupport.capture_json(name, bytes, zone, 12, Fit::Importer)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data', 'status')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'velocity', 'motion_data'))
          NormalImportFormatsSupport.write(name, result)
        end
      end
    end
  end

  context 'FIT decoder' do
    it 'records FIT decoder outcomes from fit4ruby' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.fit_reader_cases(self).each do |result|
          expect(result).to include('input', 'records', 'error')
          NormalImportFormatsSupport.write(result.fetch('name'), result.except('name'))
        end
      end
    end
  end

  context 'Whole create' do
    it 'records whole create and ZIP build failure effects' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.whole_create_cases.each do |options|
          result = NormalImportFormatsSupport.capture_whole_create(options)
          expect(result).to include('source_transition', 'parent', 'children', 'notifications', 'jobs', 'archive')
          expect(result.fetch('source_transition')).to eq(options.fetch(:expected_source))
          case options.fetch(:name)
          when 'kmz_plain'
            expect(result.fetch('children').map { |child| child.fetch('name') })
              .to eq(['_source.kmz (from plain.kmz)', 'first.KML (from plain.kmz)', 'last.kml (from plain.kmz)'])
          when 'kmz_wrapped'
            expect(result.fetch('points').map { |point| point.fetch('lonlat') }).to eq(['POINT(12.4 51.3)'])
            expect(result.fetch('kmz_leaf').fetch('name')).to eq('first.KML')
          when 'zip_later_child_failure', 'zip_extractor_later_child_failure'
            expect(result.fetch('parent').fetch('status')).to eq('failed')
            expect(result.fetch('children').map { |child| child.fetch('name') })
              .to eq(['existing-0.csv', 'existing-1.csv', 'existing-2.csv', 'first.csv (from limited.zip)'])
            expect(result.fetch('children').last.fetch('file')).to include('bytes', 'filename', 'content_type')
            expect(result.fetch('jobs').select { |job| job['type'] == 'Import::ProcessJob' }).to eq([])
          when 'csv_duplicate'
            expect(result.fetch('points')).to eq([])
            expect(result.fetch('parent')).to include('raw_points' => 2, 'doubles' => 2, 'status' => 'completed')
          when 'fit_failed_return'
            expect(result.fetch('parent').fetch('status')).to eq('failed')
          when 'v1_profile', 'v2_profile'
            expect(result.fetch('jobs')).to eq([{ 'type' => 'Users::ImportDataJob', 'args' => [987_101] }])
          when 'zip_known_preference'
            expect(result.fetch('children').map { |child| child.fetch('source') })
              .to eq(%w[google_records google_photos])
          end
          NormalImportFormatsSupport.write("whole_create/#{options.fetch(:name)}", result)
        end
      end
    end
  end

  context 'GeoJSON' do
    it 'records GeoJSON importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.geojson_cases.each do |name, bytes, zone|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_geojson(name, bytes, zone)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          commands = result['error'] ? [] : effects
          NormalImportFormatsSupport.write(name, result.merge('commands' => commands, 'attempted_commands' => effects))
        end
      end
    end
  end

  context 'OwnTracks' do
    it 'records OwnTracks importer outcomes from Rails' do
      travel_to Time.utc(2026, 1, 15, 23, 30) do
        NormalImportFormatsSupport.owntracks_cases.each do |name, bytes|
          stub_const('Point::ALTITUDE_DECIMAL_SUPPORTED', !name.end_with?('_legacy'))
          effects = []
          allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |method, user_id, timestamps:|
            effects << { 'kind' => 'points.tile_epoch', 'payload' => { 'timestamps' => timestamps } }
            method.call(user_id, timestamps:)
          end
          allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_wrap_original do |method, *args, **options|
            if options[:partial] == 'imports/table_row'
              effects << { 'kind' => 'imports.progress', 'payload' => { 'locale' => 'de' } }
            end
            method.call(*args, **options)
          end
          result = NormalImportFormatsSupport.capture_owntracks(name, bytes)
          expect(result.fetch('import')).to include('doubles', 'raw_points', 'processed', 'raw_data')
          expect(result.fetch('points')).to all(include('lonlat', 'timestamp', 'raw_data'))
          expect(result.fetch('import').fetch('doubles')).to be_a(Integer)
          NormalImportFormatsSupport.write(name, result.merge('commands' => effects))
        end
      end
    end
  end
end
