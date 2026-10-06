# frozen_string_literal: true

require 'rake'
require 'geocoder/results/photon'

module PlacesClosureCapture
  def closure_write(task, data)
    path = dir.join("a12f3a-#{task}.json")
    encoded = "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(path, encoded)
    else
      expect(JSON.parse(path.read)).to eq(JSON.parse(encoded))
    end
  end

  def capture_places_closure
    user = User.find(8401)
    data = {
      'type' => 'Feature', 'properties' => {
        'name' => 'Café <&> Leipzig', 'street' => 'Markt', 'housenumber' => '1',
        'city' => 'Leipzig', 'country' => 'Germany', 'osm_id' => 123, 'osm_type' => 'N'
      }, 'geometry' => { 'type' => 'Point', 'coordinates' => [12.3731, 51.3397] }
    }
    provider = Geocoder::Result::Photon.new(data)
    params = { latitude: '51.3397tail', longitude: '12.3731tail', radius: '1.0', limit: '3tail' }
    RSpec::Mocks.with_temporary_scope do
      configure_instance_geocoding
      allow(Geocoding::Search).to receive(:call).and_return([provider])
      sign_in user
      get('/places/nearby', params: params)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Café &lt;&amp;&gt; Leipzig')
      expected = Places::PhotonResultFormatter.call(provider, fallback_lat: 51.3397, fallback_lon: 12.3731)
      closure_write('p02', { params:, provider: data, results: [expected], status: response.status,
                             html: response.body })
      expect(Geocoding::Search).to have_received(:call).with(
        user:, query: [51.3397, 12.3731], limit: 3,
        max_wait: Geocoding::RateLimiter::MAX_INTERACTIVE_WAIT, distance_sort: true, radius: 1.0, units: :km
      )
      nearby = Places::NearbySearch.new(user:, latitude: 51.33971, longitude: 12.37311,
                                        radius: 0.5, limit: 3, cache: true)
      other = Places::NearbySearch.new(user:, latitude: 51.33972, longitude: 12.37312,
                                       radius: 1.0, limit: 3, cache: true)
      first_key = nearby.send(:cache_key)
      second_key = other.send(:cache_key)
      expect(first_key).not_to eq(second_key)
      closure_write('p03', { cache_key: first_key, other_key: second_key, ttl: 3600,
                             precision: 4, results: nearby.call })
      sign_out user
    end
    JobOutbox.delete_all
    %w[name_fetch delete_if_orphan orphan_cleanup bulk_name_fetch].each do |type|
      job_owner!("command:places.#{type}", :oban)
    end
    RailsCommands::Registry.handler('place_name_fetch').call('user_id' => user.id, 'place_id' => 840_101)
    RailsCommands::Registry.handler('places_delete_if_orphan').call('user_id' => user.id, 'place_ids' => [840_101])
    RailsCommands::Registry.handler('places_orphan_cleanup').call('user_id' => user.id)
    RailsCommands::Registry.handler('places_bulk_name_fetch').call({})
    closure_write('p06', { commands: JobOutbox.order(:command_type).map do |row|
      { type: row.command_type, version: row.command_version, payload: row.payload,
        aggregate_id: row.aggregate_id, scheduled_at: row.scheduled_at.utc.iso8601(6) }
    end })
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == 'dawarich:backfill_place_names' }
    RSpec::Mocks.with_temporary_scope do
      allow(Places::BulkNameFetchingJob).to receive(:perform_later)
      task = Rake::Task['dawarich:backfill_place_names']
      task.reenable
      task.invoke
      expect(Places::BulkNameFetchingJob).to have_received(:perform_later).once
      closure_write('p07',
                    { task: task.name, stdout: '', stderr: '',
jobs: [{ type: 'places.bulk_name_fetch', payload: {} }] })
      due = []
      allow(Places::OrphanCleanupJob).to receive(:set) do |wait:|
        instance_double(ActiveJob::ConfiguredJob).tap do |job|
          allow(job).to receive(:perform_later) { |uid| due << { user_id: uid, delay: wait.to_f } }
        end
      end
      task = Rake::Task['dawarich:cleanup_suggested_places']
      task.reenable
      task.invoke
      expected_ids = User.order(:id).pluck(:id)
      expect(due.pluck(:user_id).sort).to eq(expected_ids)
      expect(due.pluck(:delay)).to eq(expected_ids.each_index.map { |index| index * 0.1 })
      closure_write('p08', { task: task.name, stdout: '', stderr: '', jobs: due })
      orphan_count = Place.where(source: :photon, note: [nil, '']).where.missing(:visits, :taggings).count
      retained_count = nil
      unlinked_count = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        Place.insert!({ id: 848_888, user_id: user.id, name: 'Suggested place', source: 1,
                        latitude: 51.3397, longitude: 12.3731, lonlat: 'POINT(12.3731 51.3397)', **stamps })
        unlinked_count = Place.where(source: :photon, note: [nil, '']).where.missing(:visits, :taggings).count
        visit!(user, 848_888, 848_888, 'Tombstone', now - 2.days, 60, status: :declined, deleted_at: now)
        retained_count = Place.where(source: :photon, note: [nil, '']).where.missing(:visits, :taggings).count
        raise ActiveRecord::Rollback
      end
      expect(unlinked_count).to eq(orphan_count + 1)
      expect(retained_count).to eq(orphan_count)
      closure_write('p09', { count: orphan_count, stdout: "#{orphan_count}\n", stderr: '', exit: 0,
                             unlinked_count:, retained_count: })
      closure_write('p10', { backfill: 'dawarich:backfill_place_names', cleanup: task.name,
                             no_args: true, delays: due.map { |item| item[:delay] } })
    end
  end
end

RSpec.configure { |config| config.include PlacesClosureCapture }
