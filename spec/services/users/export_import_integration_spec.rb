# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users Export-Import Integration', type: :service do
  let(:original_user) { create(:user, email: 'original@example.com') }
  let(:target_user) { create(:user, email: 'target@example.com') }
  let(:temp_archive_path) { Rails.root.join('tmp/test_export.zip') }

  after do
    File.delete(temp_archive_path) if File.exist?(temp_archive_path)
  end

  describe 'complete export-import cycle' do
    before do
      create_full_user_dataset(original_user)
    end

    it 'exports and imports all user data while preserving relationships' do
      export_record = Users::ExportData.new(original_user).export

      expect(export_record).to be_present
      expect(export_record.status).to eq('completed')
      expect(export_record.file).to be_attached

      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      expect(File.exist?(temp_archive_path)).to be true

      original_counts = calculate_user_entity_counts(original_user)

      original_log_level = Rails.logger.level
      Rails.logger.level = Logger::DEBUG

      begin
        import_stats = Users::ImportData.new(target_user, temp_archive_path).import
      ensure
        Rails.logger.level = original_log_level
      end

      user_notifications_count = original_user.notifications.where.not(
        title: ['Data import completed', 'Data import failed', 'Export completed', 'Export failed']
      ).count

      target_counts = calculate_user_entity_counts(target_user)

      expect(target_counts[:areas]).to eq(original_counts[:areas])
      expect(target_counts[:imports]).to eq(original_counts[:imports])
      expect(target_counts[:exports]).to eq(original_counts[:exports])
      expect(target_counts[:trips]).to eq(original_counts[:trips])
      expect(target_counts[:stats]).to eq(original_counts[:stats])
      expect(target_counts[:notifications]).to eq(user_notifications_count + 1)
      expect(target_counts[:points]).to eq(original_counts[:points])
      expect(target_counts[:visits]).to eq(original_counts[:visits])
      expect(target_counts[:places]).to eq(original_counts[:places])
      expect(target_counts[:tags]).to eq(original_counts[:tags])
      expect(target_counts[:tracks]).to eq(original_counts[:tracks])
      expect(target_counts[:digests]).to eq(original_counts[:digests])

      # Verify import stats match expectations
      expect(import_stats[:areas_created]).to eq(original_counts[:areas])
      expect(import_stats[:imports_created]).to eq(original_counts[:imports])
      expect(import_stats[:exports_created]).to eq(original_counts[:exports])
      expect(import_stats[:trips_created]).to eq(original_counts[:trips])
      expect(import_stats[:stats_created]).to eq(original_counts[:stats])
      expect(import_stats[:notifications_created]).to eq(user_notifications_count)
      expect(import_stats[:points_created]).to eq(original_counts[:points])
      expect(import_stats[:visits_created]).to eq(original_counts[:visits])
      expect(import_stats[:tags_created]).to eq(original_counts[:tags])
      expect(import_stats[:tracks_created]).to eq(original_counts[:tracks])
      expect(import_stats[:digests_created]).to eq(original_counts[:digests])
      # Places are global entities, so they may already exist and not be recreated
      # The count in target_counts shows the user has access to the places (through visits)

      verify_relationships_preserved(original_user, target_user)

      verify_settings_preserved(original_user, target_user)

      verify_files_restored(original_user, target_user)
    end

    it 'is idempotent - running import twice does not create duplicates' do
      export_record = Users::ExportData.new(original_user).export

      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      Users::ImportData.new(target_user, temp_archive_path).import
      first_counts = calculate_user_entity_counts(target_user)

      second_import_stats = Users::ImportData.new(target_user, temp_archive_path).import
      second_counts = calculate_user_entity_counts(target_user)

      expect(second_counts[:areas]).to eq(first_counts[:areas])
      expect(second_counts[:imports]).to eq(first_counts[:imports])
      expect(second_counts[:exports]).to eq(first_counts[:exports])
      expect(second_counts[:trips]).to eq(first_counts[:trips])
      expect(second_counts[:stats]).to eq(first_counts[:stats])
      expect(second_counts[:points]).to eq(first_counts[:points])
      expect(second_counts[:visits]).to eq(first_counts[:visits])
      expect(second_counts[:places]).to eq(first_counts[:places])
      expect(second_counts[:tags]).to eq(first_counts[:tags])
      expect(second_counts[:tracks]).to eq(first_counts[:tracks])
      expect(second_counts[:digests]).to eq(first_counts[:digests])
      expect(second_counts[:notifications]).to eq(first_counts[:notifications] + 1)

      expect(second_import_stats[:areas_created]).to eq(0)
      expect(second_import_stats[:imports_created]).to eq(0)
      expect(second_import_stats[:exports_created]).to eq(0)
      expect(second_import_stats[:trips_created]).to eq(0)
      expect(second_import_stats[:stats_created]).to eq(0)
      expect(second_import_stats[:notifications_created]).to eq(0)
      expect(second_import_stats[:points_created]).to eq(0)
      expect(second_import_stats[:visits_created]).to eq(0)
      expect(second_import_stats[:places_created]).to eq(0)
      expect(second_import_stats[:tags_created]).to eq(0)
      expect(second_import_stats[:tracks_created]).to eq(0)
      expect(second_import_stats[:digests_created]).to eq(0)
    end

    it 'does not trigger background processing for imported imports' do
      expect(Import::ProcessJob).not_to receive(:perform_later)

      export_record = Users::ExportData.new(original_user).export

      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      Users::ImportData.new(target_user, temp_archive_path).import
    end
  end

  describe 'places and visits import integrity' do
    it 'imports all places and visits without losses due to global deduplication' do
      # Create a user with specific places and visits
      original_user = create(:user, email: 'original@example.com')

      # Create places with different characteristics
      home_place = create(:place, user: original_user, name: 'Home', latitude: 40.7128, longitude: -74.0060)
      office_place = create(:place, user: original_user, name: 'Office', latitude: 40.7589, longitude: -73.9851)
      gym_place = create(:place, user: original_user, name: 'Gym', latitude: 40.7505, longitude: -73.9934)

      # Create visits associated with those places
      create(:visit, user: original_user, place: home_place, name: 'Home Visit')
      create(:visit, user: original_user, place: office_place, name: 'Work Visit')
      create(:visit, user: original_user, place: gym_place, name: 'Workout')

      # Create a visit without a place
      create(:visit, user: original_user, place: nil, name: 'Unknown Location')

      # Calculate counts properly - places are accessed through visits
      original_places_count = original_user.visited_places.distinct.count
      original_visits_count = original_user.visits.count

      # Export the data
      export_service = Users::ExportData.new(original_user)
      export_record = export_service.export

      # Download and save to a temporary file for processing
      archive_content = export_record.file.download
      temp_export_file = Tempfile.new(['test_export', '.zip'])
      temp_export_file.binmode
      temp_export_file.write(archive_content)
      temp_export_file.close

      # SIMULATE FRESH DATABASE: Remove the original places to simulate database migration
      # This simulates the scenario where we're importing into a different database
      place_ids_to_remove = [home_place.id, office_place.id, gym_place.id]
      Place.where(id: place_ids_to_remove).destroy_all

      # Create another user on a "different database" scenario
      import_user = create(:user, email: 'import@example.com')

      # Create some existing global places that might conflict
      # These should NOT prevent import of the user's places
      create(:place, name: 'Home', latitude: 40.8000, longitude: -74.1000) # Different coordinates
      create(:place, name: 'Coffee Shop', latitude: 40.7589, longitude: -73.9851) # Same coordinates, different name

      # Simulate import into "new database"
      temp_import_file = Tempfile.new(['test_import', '.zip'])
      temp_import_file.binmode
      temp_import_file.write(archive_content)
      temp_import_file.close

      # Import the data
      import_service = Users::ImportData.new(import_user, temp_import_file.path)
      import_stats = import_service.import

      # Verify all entities were imported correctly
      expect(import_stats[:places_created]).to \
        eq(original_places_count),
        "Expected #{original_places_count} places to be created, got #{import_stats[:places_created]}"
      expect(import_stats[:visits_created]).to \
        eq(original_visits_count),
        "Expected #{original_visits_count} visits to be created, got #{import_stats[:visits_created]}"

      # Verify the imported user has access to all their data
      imported_places_count = import_user.visited_places.distinct.count
      imported_visits_count = import_user.visits.count

      expect(imported_places_count).to \
        eq(original_places_count),
        "Expected user to have access to #{original_places_count} places, got #{imported_places_count}"
      expect(imported_visits_count).to \
        eq(original_visits_count),
        "Expected user to have #{original_visits_count} visits, got #{imported_visits_count}"

      # Verify specific visits have their place associations
      imported_visits = import_user.visits.includes(:place)
      visits_with_places = imported_visits.where.not(place: nil)
      expect(visits_with_places.count).to eq(3) # Home, Office, Gym

      # Verify place names are preserved
      place_names = visits_with_places.map { |v| v.place.name }.sort
      expect(place_names).to eq(%w[Gym Home Office])

      # Cleanup
      temp_export_file.unlink
      temp_import_file.unlink
    end
  end

  private

  def create_full_user_dataset(user)
    user.update!(settings:
      {
        'distance_unit' => 'km',
        'timezone' => 'America/New_York',
        'immich_url' => 'https://immich.example.com',
        'immich_api_key' => 'test-api-key'
      })

    usa = create(:country, name: 'United States', iso_a2: 'US', iso_a3: 'USA')
    canada = create(:country, name: 'Canada', iso_a2: 'CA', iso_a3: 'CAN')

    office = create(:place, name: 'Office Building', latitude: 40.7589, longitude: -73.9851)
    home = create(:place, name: 'Home Sweet Home', latitude: 40.7128, longitude: -74.0060)

    create_list(:area, 3, user: user)

    import1 = create(:import, user: user, name: 'March 2024 Data', source: :google_semantic_history)
    import2 = create(:import, user: user, name: 'OwnTracks Data', source: :owntracks)

    import1.file.attach(
      io: StringIO.new('{"timelineObjects": []}'),
      filename: 'march_2024.json',
      content_type: 'application/json'
    )
    import2.file.attach(
      io: StringIO.new('{"_type": "location"}'),
      filename: 'owntracks.json',
      content_type: 'application/json'
    )

    export1 = create(:export, user: user, name: 'Q1 2024 Export', file_format: :json, file_type: :points)
    export1.file.attach(
      io: StringIO.new('{"type": "FeatureCollection", "features": []}'),
      filename: 'q1_2024.json',
      content_type: 'application/json'
    )

    export2 = create(:export, user: user, name: 'Q2 2024 Export', file_format: :json, file_type: :user_data)
    export2.file.attach(
      io: StringIO.new('{"type": "FeatureCollection", "features": []}'),
      filename: 'q2_2024.json',
      content_type: 'application/json'
    )

    create_list(:trip, 2, user: user)

    create(:stat, user: user, year: 2024, month: 1, distance: 150.5, daily_distance: [[1, 5.2], [2, 8.1]])
    create(:stat, user: user, year: 2024, month: 2, distance: 200.3, daily_distance: [[1, 6.5], [2, 9.8]])

    create_list(:notification, 4, user: user)

    visit1 = create(:visit, user: user, place: office, name: 'Work Visit')
    visit2 = create(:visit, user: user, place: home, name: 'Home Visit')
    visit3 = create(:visit, user: user, place: nil, name: 'Unknown Location')

    create_list(:point, 5,
                user: user,
                import: import1,
                country: usa,
                visit: visit1,
                latitude: 40.7589,
                longitude: -73.9851)

    create_list(:point, 3,
                user: user,
                import: import2,
                country: canada,
                visit: visit2,
                latitude: 40.7128,
                longitude: -74.0060)

    create_list(:point, 2,
                user: user,
                import: nil,
                country: nil,
                visit: nil)

    create_list(:point, 2,
                user: user,
                import: import1,
                country: usa,
                visit: visit3)

    # Tags and taggings
    home_tag = create(:tag, user: user, name: 'Home', icon: '🏠', color: '#4CAF50')
    work_tag = create(:tag, user: user, name: 'Work', icon: '🏢', color: '#2196F3')
    Tagging.create!(tag: home_tag, taggable: home)
    Tagging.create!(tag: work_tag, taggable: office)

    # Tracks with segments
    track1 = create(:track, user: user,
                            start_at: Time.utc(2024, 1, 15, 8),
                            end_at: Time.utc(2024, 1, 15, 9))
    create(:track_segment, track: track1, transportation_mode: :driving)

    track2 = create(:track, user: user,
                            start_at: Time.utc(2024, 2, 20, 10),
                            end_at: Time.utc(2024, 2, 20, 11))
    create(:track_segment, track: track2, transportation_mode: :walking)

    # Digests
    create(:users_digest, :monthly, user: user, year: 2024, month: 1)
    create(:users_digest, user: user, year: 2024)
  end

  def calculate_user_entity_counts(user)
    {
      areas: user.areas.count,
      imports: user.imports.count,
      exports: user.exports.count,
      trips: user.trips.count,
      stats: user.stats.count,
      notifications: user.notifications.count,
      points: user.points.count,
      visits: user.visits.count,
      places: user.visited_places.count,
      tags: user.tags.count,
      tracks: user.tracks.count,
      digests: user.digests.count
    }
  end

  def verify_relationships_preserved(original_user, target_user)
    original_points_with_imports = original_user.points.where.not(import_id: nil).count
    target_points_with_imports = target_user.points.where.not(import_id: nil).count
    expect(target_points_with_imports).to eq(original_points_with_imports)

    original_points_with_countries = original_user.points.where.not(country_id: nil).count
    target_points_with_countries = target_user.points.where.not(country_id: nil).count
    expect(target_points_with_countries).to eq(original_points_with_countries)

    original_points_with_visits = original_user.points.where.not(visit_id: nil).count
    target_points_with_visits = target_user.points.where.not(visit_id: nil).count
    expect(target_points_with_visits).to eq(original_points_with_visits)

    original_visits_with_places = original_user.visits.where.not(place_id: nil).count
    target_visits_with_places = target_user.visits.where.not(place_id: nil).count
    expect(target_visits_with_places).to eq(original_visits_with_places)

    original_office_points = original_user.points.where(
      latitude: 40.7589, longitude: -73.9851
    ).first
    target_office_points = target_user.points.where(
      latitude: 40.7589, longitude: -73.9851
    ).first

    return unless original_office_points && target_office_points

    expect(target_office_points.import.name).to eq(original_office_points.import.name) if original_office_points.import
    if original_office_points.country
      expect(target_office_points.country.name).to eq(original_office_points.country.name)
    end
    expect(target_office_points.visit.name).to eq(original_office_points.visit.name) if original_office_points.visit
  end

  def verify_settings_preserved(original_user, target_user)
    expect(target_user.safe_settings.distance_unit).to eq(original_user.safe_settings.distance_unit)
    expect(target_user.settings['timezone']).to eq(original_user.settings['timezone'])
    expect(target_user.settings['immich_url']).to eq(original_user.settings['immich_url'])
    expect(target_user.settings['immich_api_key']).to eq(original_user.settings['immich_api_key'])
  end

  def verify_files_restored(original_user, target_user)
    verify_import_files_restored(original_user, target_user)
    verify_export_files_restored(original_user, target_user)
  end

  def verify_import_files_restored(original_user, target_user)
    original_imports_with_files = original_user.imports.joins(:file_attachment).count
    target_imports_with_files = target_user.imports.joins(:file_attachment).count
    expect(target_imports_with_files).to eq(original_imports_with_files)

    original_import = original_user.imports.find_by(name: 'March 2024 Data')
    target_import = target_user.imports.find_by(name: 'March 2024 Data')

    return unless original_import&.file&.attached? && target_import&.file&.attached?

    expect(target_import.file.filename.to_s).to eq(original_import.file.filename.to_s)
    expect(target_import.file.content_type).to eq(original_import.file.content_type)
  end

  def verify_export_files_restored(original_user, target_user)
    target_exports_with_files = target_user.exports.joins(:file_attachment).count
    expect(target_exports_with_files).to be >= 2

    original_export = original_user.exports.find_by(name: 'Q1 2024 Export')
    return unless original_export&.file&.attached?

    target_export = target_user.exports.find_by(name: 'Q1 2024 Export')
    expect(target_export).to be_present
    expect(target_export.file).to be_attached
  end

  describe 'v1 format backward compatibility' do
    # This test verifies that the new import system can still read v1 format archives
    # (single data.json file instead of JSONL with monthly splitting)

    let(:import_user) { create(:user, email: 'v1_import@example.com') }
    let(:v1_archive_path) { Rails.root.join('tmp/v1_test_archive.zip') }

    after do
      File.delete(v1_archive_path) if File.exist?(v1_archive_path)
    end

    it 'imports v1 format archive (data.json) correctly' do
      # Create a v1 format archive with data.json
      v1_data = {
        counts: {
          areas: 2,
          imports: 0,
          exports: 0,
          trips: 1,
          stats: 1,
          notifications: 1,
          points: 3,
          visits: 1,
          places: 1
        },
        settings: {
          'distance_unit' => 'mi',
          'timezone' => 'America/New_York'
        },
        areas: [
          { 'name' => 'V1 Home', 'latitude' => 40.7128, 'longitude' => -74.006, 'radius' => 100 },
          { 'name' => 'V1 Work', 'latitude' => 40.7589, 'longitude' => -73.9851, 'radius' => 50 }
        ],
        imports: [],
        exports: [],
        trips: [
          {
            'name' => 'V1 Trip',
            'started_at' => '2023-06-01T08:00:00Z',
            'ended_at' => '2023-06-01T18:00:00Z',
            'distance' => 50
          }
        ],
        stats: [
          { 'year' => 2023, 'month' => 6, 'distance' => 150 }
        ],
        notifications: [
          { 'title' => 'V1 Notification', 'content' => 'From v1 export', 'kind' => 'info' }
        ],
        places: [
          { 'name' => 'V1 Place', 'latitude' => 40.75, 'longitude' => -73.99, 'source' => 'manual' }
        ],
        visits: [
          {
            'name' => 'V1 Visit',
            'started_at' => '2023-06-01T09:00:00Z',
            'ended_at' => '2023-06-01T17:00:00Z',
            'duration' => 28_800,
            'status' => 'confirmed',
            'place_reference' => {
              'name' => 'V1 Place',
              'latitude' => '40.75',
              'longitude' => '-73.99',
              'source' => 'manual'
            }
          }
        ],
        points: [
          {
            'timestamp' => 1_685_606_400,
            'longitude' => -74.006,
            'latitude' => 40.7128,
            'lonlat' => 'POINT(-74.006 40.7128)',
            'city' => 'New York'
          },
          {
            'timestamp' => 1_685_610_000,
            'longitude' => -73.99,
            'latitude' => 40.75,
            'lonlat' => 'POINT(-73.99 40.75)'
          },
          {
            'timestamp' => 1_685_613_600,
            'longitude' => -73.9851,
            'latitude' => 40.7589,
            'lonlat' => 'POINT(-73.9851 40.7589)'
          }
        ]
      }

      # Create v1 format zip with data.json (no manifest.json)
      Zip::File.open(v1_archive_path, create: true) do |zipfile|
        zipfile.get_output_stream('data.json') do |f|
          f.write(v1_data.to_json)
        end
        # Create empty files directory
        zipfile.mkdir('files')
      end

      # Import using the new system
      import_stats = Users::ImportData.new(import_user, v1_archive_path).import

      # Verify all data was imported correctly
      expect(import_stats[:settings_updated]).to be true
      expect(import_stats[:areas_created]).to eq(2)
      expect(import_stats[:trips_created]).to eq(1)
      expect(import_stats[:stats_created]).to eq(1)
      expect(import_stats[:notifications_created]).to eq(1)
      expect(import_stats[:visits_created]).to eq(1)
      expect(import_stats[:points_created]).to eq(3)

      # Verify specific data
      expect(import_user.reload.settings['distance_unit']).to eq('mi')
      expect(import_user.areas.pluck(:name)).to contain_exactly('V1 Home', 'V1 Work')
      expect(import_user.trips.find_by(name: 'V1 Trip')).to be_present
      expect(import_user.stats.find_by(year: 2023, month: 6)).to be_present
      expect(import_user.visits.find_by(name: 'V1 Visit')).to be_present
      expect(import_user.points.count).to eq(3)
    end
  end

  describe 'v2 format export creates correct structure' do
    let(:export_user) { create(:user, email: 'v2_export@example.com') }

    before do
      # Create some data
      create(:area, user: export_user, name: 'Test Area')
      create(:point, user: export_user, timestamp: Time.utc(2024, 1, 15).to_i)
      create(:point, user: export_user, timestamp: Time.utc(2024, 6, 20).to_i)
      create(:stat, user: export_user, year: 2024, month: 1)
    end

    it 'exports with manifest.json and JSONL files' do
      export_record = Users::ExportData.new(export_user).export

      expect(export_record.status).to eq('completed')
      expect(export_record.file).to be_attached

      # Extract and verify structure
      temp_dir = Rails.root.join('tmp/v2_structure_test')
      FileUtils.mkdir_p(temp_dir)

      begin
        archive_content = export_record.file.download
        temp_zip = temp_dir.join('export.zip')
        File.binwrite(temp_zip, archive_content)

        Zip::File.open(temp_zip) do |zipfile|
          # Verify manifest exists
          manifest_entry = zipfile.find_entry('manifest.json')
          expect(manifest_entry).not_to be_nil

          manifest = JSON.parse(manifest_entry.get_input_stream.read)
          expect(manifest['format_version']).to eq(2)
          expect(manifest['files']['points']).to be_an(Array)
          expect(manifest['files']['points']).to include('points/2024/2024-01.jsonl')
          expect(manifest['files']['points']).to include('points/2024/2024-06.jsonl')

          # Verify JSONL files exist
          expect(zipfile.find_entry('areas.jsonl')).not_to be_nil
          expect(zipfile.find_entry('settings.jsonl')).not_to be_nil

          # Verify monthly files exist
          expect(zipfile.find_entry('points/2024/2024-01.jsonl')).not_to be_nil
          expect(zipfile.find_entry('points/2024/2024-06.jsonl')).not_to be_nil
          expect(zipfile.find_entry('stats/2024/2024-01.jsonl')).not_to be_nil

          # Verify data.json does NOT exist (v2 format)
          expect(zipfile.find_entry('data.json')).to be_nil
        end
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end
  end
end
