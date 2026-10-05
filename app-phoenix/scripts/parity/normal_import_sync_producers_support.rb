# frozen_string_literal: true

module NormalImportFormatsSupport
  module_function

  def capture_teslamate_producer
    %w[success km duplicate incomplete quota disconnected scheduling].to_h do |name|
      url = 'http://127.0.0.1:19992'
      value = capture_producer('teslamate_url' => url) do |user, requests, observer|
        units = { unit_of_length: name == 'km' ? 'km' : 'mi' }
        bodies = {
          '/api/v1/cars' => { data: { cars: [{ car_id: 1 }] } },
          '/api/v1/cars/1/drives' => { data: { drives: [{ drive_id: 11 }], units: } },
          '/api/v1/cars/1/drives/11' => {
            data: { drive: { drive_details: [
              { detail_id: 111, date: '2026-01-15T23:30:00Z', latitude: 51.3, longitude: 12.4,
                elevation: 12.75, speed: 10, battery_level: 80 },
              { detail_id: 112, date: 'invalid', latitude: 51.3, longitude: 12.4 }
            ] }, units: }
          }
        }
        bodies['/api/v1/cars/1/drives/11'] = { data: { drive: {} } } if name == 'incomplete'
        bodies.each do |path, payload|
          observer.stub_request(:get, /#{Regexp.escape(url + path)}(?:\?|$)/).to_return do |request|
            body = payload.to_json
            requests << { 'path' => path, 'query' => CGI.parse(request.uri.query.to_s), 'body' => body }
            { status: 200, body:, headers: { 'content-type' => 'application/json' } }
          end
        end
        if name == 'quota'
          observer.allow(DawarichSettings).to observer.receive(:self_hosted?).and_return(false)
          user.update_columns(points_count: DawarichSettings::BASIC_PAID_PLAN_LIMIT)
        end
        user.update_columns(settings: user.settings.merge('teslamate_url' => '')) if name == 'disconnected'
        if name == 'scheduling'
          TeslaMate::SyncSchedulingJob.new.perform
          nil
        else
          result = TeslaMate::Sync.new(user.reload).call
          TeslaMate::SyncJob.new.perform(user.id) if name == 'duplicate'
          result
        end
      end
      [name, value]
    end
  end

  def capture_trek_producer
    %w[success duplicate stopped incomplete unauthorized disconnected continuation sync_scheduling].to_h do |name|
      value = capture_producer do |user, requests, observer|
        observer.extend(HostAddressStubs).stub_host_addresses('trek.example.test', '93.184.216.34')
        source = TripSource.new(id: 987_401, user:, provider: 'trek', base_url: 'https://trek.example.test',
                                api_key: 'synthetic-provider-fixture', selection_token: 'synthetic-selection')
        source.save!(validate: false)
        observer.allow_any_instance_of(TripSource)
                .to observer.receive(:resolved_base_url_ip!).and_return('93.184.216.34')
        payload = { id: 'selected', title: 'Synthetic itinerary', start_date: '2030-01-01', end_date: '2030-01-02',
                    days: [{ date: '2030-01-01', day_number: 1,
                             places: [{ name: 'Synthetic stop', lat: 51.3, lng: 12.4, duration_minutes: 30 }] }],
                    accommodations: [], travellers: [] }
        listing = { trips: [{ id: 'selected', archived: name == 'stopped' }] }
        observer.stub_request(:get, 'https://trek.example.test/api/v1/trips').to_return do
          requests << { 'path' => '/api/v1/trips', 'body' => listing.to_json }
          { status: 200, body: listing.to_json }
        end
        detail = name == 'incomplete' ? {} : payload
        observer.stub_request(:get, 'https://trek.example.test/api/v1/trips/selected').to_return do
          status = name == 'unauthorized' ? 401 : 200
          requests << { 'path' => '/api/v1/trips/selected', 'body' => detail.to_json, 'status' => status }
          { status:, body: detail.to_json }
        end
        observer.stub_request(:get, %r{https://trek.example.test/api/v1/trips/draft-\d+}).to_return do |request|
          body = { id: request.uri.path.split('/').last, start_date: nil, end_date: nil }.to_json
          requests << { 'path' => request.uri.path, 'body' => body, 'status' => 200 }
          { status: 200, body: }
        end
        result = nil
        begin
          case name
          when 'continuation'
            source.update!(importing: true)
            identifiers = 100.times.map { |index| "draft-#{index}" } + ['selected']
            Trek::ImportTripsJob.new.perform(source.id, identifiers, source.selection_token)
          when 'sync_scheduling'
            Trek::SyncSchedulingJob.new.perform
          when 'disconnected'
            source.update!(status: :disabled, importing: true)
            Trek::ImportTripsJob.new.perform(source.id, ['selected'], source.selection_token)
            Trek::SyncJob.new.perform(source.id)
          when 'success'
            source.update!(importing: true)
            Trek::ImportTripsJob.new.perform(source.id, ['selected'], source.selection_token)
          when 'duplicate', 'stopped'
            synchronizer = Trek::Sync.new(source)
            _, created, changed = synchronizer.import!('selected')
            result = { 'created' => created, 'changed' => changed }
            result['sync'] = synchronizer.call.to_h if name != 'success'
            Trek::SyncJob.new.perform(source.id) if name == 'duplicate'
          else
            source.update!(importing: true)
            Trek::ImportTripsJob.new.perform(source.id, ['selected'], source.selection_token)
          end
        rescue StandardError => e
          failure = { 'class' => e.class.name, 'message' => e.message }
        end
        { 'result' => result, 'error' => failure,
          'source' => source.reload.attributes.slice('id', 'provider', 'status', 'importing',
                                                     'last_error', 'last_synced_at'),
          'trips' => source.trips.order(:id).map do |trip|
            trip.attributes.slice('id', 'name', 'source_identifier', 'source_status', 'source_snapshot',
                                  'source_digest', 'started_at', 'ended_at', 'source_synced_at')
          end,
          'itinerary' => source.trips.order(:id).flat_map do |trip|
            trip.planned_days.order(:date).map do |day|
              { 'date' => day.date, 'day_number' => day.position,
                'places' => day.planned_stops.order(:position).map do |place|
                  place.attributes.slice('name', 'latitude', 'longitude', 'position', 'duration_minutes')
                end }
            end
          end }
      end
      [name, value]
    end
  end
end
