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

      # Verify import stats match expectations
      expect(import_stats[:areas_created]).to eq(original_counts[:areas])
      expect(import_stats[:imports_created]).to eq(original_counts[:imports])
      expect(import_stats[:exports_created]).to eq(original_counts[:exports])
      expect(import_stats[:trips_created]).to eq(original_counts[:trips])
      expect(import_stats[:stats_created]).to eq(original_counts[:stats])
      expect(import_stats[:notifications_created]).to eq(user_notifications_count)
      expect(import_stats[:points_created]).to eq(original_counts[:points])
      expect(import_stats[:visits_created]).to eq(original_counts[:visits])
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

      first_import_stats = Users::ImportData.new(target_user, temp_archive_path).import
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
      home_place = create(:place, name: 'Home', latitude: 40.7128, longitude: -74.0060)
      office_place = create(:place, name: 'Office', latitude: 40.7589, longitude: -73.9851)
      gym_place = create(:place, name: 'Gym', latitude: 40.7505, longitude: -73.9934)

      # Create visits associated with those places
      create(:visit, user: original_user, place: home_place, name: 'Home Visit')
      create(:visit, user: original_user, place: office_place, name: 'Work Visit')
      create(:visit, user: original_user, place: gym_place, name: 'Workout')

      # Create a visit without a place
      create(:visit, user: original_user, place: nil, name: 'Unknown Location')

      # Calculate counts properly - places are accessed through visits
      original_places_count = original_user.places.distinct.count
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
      imported_places_count = import_user.places.distinct.count
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
      places: user.places.count
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
    original_imports_with_files = original_user.imports.joins(:file_attachment).count
    target_imports_with_files = target_user.imports.joins(:file_attachment).count
    expect(target_imports_with_files).to eq(original_imports_with_files)

    target_exports_with_files = target_user.exports.joins(:file_attachment).count
    expect(target_exports_with_files).to be >= 2

    original_import = original_user.imports.find_by(name: 'March 2024 Data')
    target_import = target_user.imports.find_by(name: 'March 2024 Data')

    if original_import&.file&.attached? && target_import&.file&.attached?
      expect(target_import.file.filename.to_s).to eq(original_import.file.filename.to_s)
      expect(target_import.file.content_type).to eq(original_import.file.content_type)
    end

    original_export = original_user.exports.find_by(name: 'Q1 2024 Export')
    target_export = target_user.exports.find_by(name: 'Q1 2024 Export')

    return unless original_export&.file&.attached?

    expect(target_export).to be_present
    expect(target_export.file).to be_attached
  end
end
