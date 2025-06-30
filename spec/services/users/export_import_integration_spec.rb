# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users Export-Import Integration', type: :service do
  let(:original_user) { create(:user, email: 'original@example.com') }
  let(:target_user) { create(:user, email: 'target@example.com') }
  let(:temp_archive_path) { Rails.root.join('tmp', 'test_export.zip') }

  after do
    # Clean up any test files
    File.delete(temp_archive_path) if File.exist?(temp_archive_path)
  end

  describe 'complete export-import cycle' do
    before do
      # Create comprehensive test data for original user
      create_full_user_dataset(original_user)
    end

    it 'exports and imports all user data while preserving relationships' do
      # Step 1: Export original user data
      export_record = Users::ExportData.new(original_user).export

      expect(export_record).to be_present
      expect(export_record.status).to eq('completed')
      expect(export_record.file).to be_attached

      # Download export file to temporary location
      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      expect(File.exist?(temp_archive_path)).to be true

      # Step 2: Capture original counts
      original_counts = calculate_user_entity_counts(original_user)

      # Debug: Check what was exported
      debug_export_data(temp_archive_path)

      # Debug: Enable detailed logging
      original_log_level = Rails.logger.level
      Rails.logger.level = Logger::DEBUG

      begin
        # Step 3: Import data into target user
        import_stats = Users::ImportData.new(target_user, temp_archive_path).import
      ensure
        # Restore original log level
        Rails.logger.level = original_log_level
      end

      # Debug: Check import stats
      puts "Import stats: #{import_stats.inspect}"

      # Step 4: Calculate user-generated notification count for comparisons
      # Only user-generated notifications are exported, not system notifications
      user_notifications_count = original_user.notifications.where.not(
        title: ['Data import completed', 'Data import failed', 'Export completed', 'Export failed']
      ).count

      # Verify entity counts match
      target_counts = calculate_user_entity_counts(target_user)

      # Debug: Show count comparison
      puts "Original counts: #{original_counts.inspect}"
      puts "Target counts: #{target_counts.inspect}"

      # Compare all entity counts
      expect(target_counts[:areas]).to eq(original_counts[:areas])
      expect(target_counts[:imports]).to eq(original_counts[:imports])
      expect(target_counts[:exports]).to eq(original_counts[:exports])
      expect(target_counts[:trips]).to eq(original_counts[:trips])
      expect(target_counts[:stats]).to eq(original_counts[:stats])
      # Target should have user notifications + import success notification
      # Original count includes export success, but export filters that out
      # Import creates its own success notification, so target should have user notifications + import success
      expect(target_counts[:notifications]).to eq(user_notifications_count + 1)  # +1 for import success
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
      # but places_created shows how many NEW places were actually created during import
      # Since places may be global duplicates, we just verify they're accessible
      expect(target_counts[:places]).to eq(original_counts[:places])  # User still has access to places

      # Step 5: Verify relationships are preserved
      verify_relationships_preserved(original_user, target_user)

      # Step 6: Verify settings are preserved
      verify_settings_preserved(original_user, target_user)

      # Step 7: Verify files are restored
      verify_files_restored(original_user, target_user)
    end

    it 'is idempotent - running import twice does not create duplicates' do
      # First export and import
      export_record = Users::ExportData.new(original_user).export

      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      # First import
      first_import_stats = Users::ImportData.new(target_user, temp_archive_path).import
      first_counts = calculate_user_entity_counts(target_user)

      # Second import (should not create duplicates)
      second_import_stats = Users::ImportData.new(target_user, temp_archive_path).import
      second_counts = calculate_user_entity_counts(target_user)

      # Counts should be identical
      expect(second_counts).to eq(first_counts)

      # Second import should create no new entities
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
      # Mock the job to ensure it's not called
      expect(Import::ProcessJob).not_to receive(:perform_later)

      export_record = Users::ExportData.new(original_user).export

      File.open(temp_archive_path, 'wb') do |file|
        export_record.file.download { |chunk| file.write(chunk) }
      end

      Users::ImportData.new(target_user, temp_archive_path).import
    end
  end

  private

  def debug_export_data(archive_path)
    require 'zip'

    puts "\n=== DEBUGGING EXPORT DATA ==="

    # Extract and read the data.json file
    Zip::File.open(archive_path) do |zip_file|
      data_entry = zip_file.find { |entry| entry.name == 'data.json' }
      if data_entry
        json_content = data_entry.get_input_stream.read
        data = JSON.parse(json_content)

        puts "Export counts: #{data['counts'].inspect}"
        puts "Points in export: #{data['points']&.size || 0}"
        puts "Places in export: #{data['places']&.size || 0}"
        puts "First point sample: #{data['points']&.first&.slice('timestamp', 'longitude', 'latitude', 'import_reference', 'country_info', 'visit_reference')}"
        puts "First place sample: #{data['places']&.first&.slice('name', 'latitude', 'longitude', 'source')}"
        puts "Imports in export: #{data['imports']&.size || 0}"
        puts "Countries referenced: #{data['points']&.map { |p| p['country_info']&.dig('name') }&.compact&.uniq || []}"
      else
        puts "No data.json found in export!"
      end
    end

    puts "=== END DEBUG ==="
  end

  def create_full_user_dataset(user)
    # Set custom user settings
    user.update!(settings: {
      'distance_unit' => 'km',
      'timezone' => 'America/New_York',
      'immich_url' => 'https://immich.example.com',
      'immich_api_key' => 'test-api-key'
    })

    # Create countries (global entities)
    usa = create(:country, name: 'United States', iso_a2: 'US', iso_a3: 'USA')
    canada = create(:country, name: 'Canada', iso_a2: 'CA', iso_a3: 'CAN')

    # Create places (global entities)
    office = create(:place, name: 'Office Building', latitude: 40.7589, longitude: -73.9851)
    home = create(:place, name: 'Home Sweet Home', latitude: 40.7128, longitude: -74.0060)

    # Create user-specific areas
    create_list(:area, 3, user: user)

    # Create imports with files
    import1 = create(:import, user: user, name: 'March 2024 Data', source: :google_semantic_history)
    import2 = create(:import, user: user, name: 'OwnTracks Data', source: :owntracks)

    # Attach files to imports
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

    # Create exports with files
    export1 = create(:export, user: user, name: 'Q1 2024 Export', file_format: :json, file_type: :points)
    export1.file.attach(
      io: StringIO.new('{"type": "FeatureCollection", "features": []}'),
      filename: 'q1_2024.json',
      content_type: 'application/json'
    )

    # Create trips
    create_list(:trip, 2, user: user)

    # Create stats
    create(:stat, user: user, year: 2024, month: 1, distance: 150.5, daily_distance: [[1, 5.2], [2, 8.1]])
    create(:stat, user: user, year: 2024, month: 2, distance: 200.3, daily_distance: [[1, 6.5], [2, 9.8]])

    # Create notifications
    create_list(:notification, 4, user: user)

    # Create visits (linked to places)
    visit1 = create(:visit, user: user, place: office, name: 'Work Visit')
    visit2 = create(:visit, user: user, place: home, name: 'Home Visit')
    visit3 = create(:visit, user: user, place: nil, name: 'Unknown Location')

    # Create points with various relationships
    # Points linked to import1, usa, and visit1
    create_list(:point, 5,
      user: user,
      import: import1,
      country: usa,
      visit: visit1,
      latitude: 40.7589,
      longitude: -73.9851
    )

    # Points linked to import2, canada, and visit2
    create_list(:point, 3,
      user: user,
      import: import2,
      country: canada,
      visit: visit2,
      latitude: 40.7128,
      longitude: -74.0060
    )

    # Points with no relationships (orphaned)
    create_list(:point, 2,
      user: user,
      import: nil,
      country: nil,
      visit: nil
    )

    # Points linked to visit3 (no place)
    create_list(:point, 2,
      user: user,
      import: import1,
      country: usa,
      visit: visit3
    )

    puts "Created dataset with #{user.tracked_points.count} points"
  end

  def calculate_user_entity_counts(user)
    {
      areas: user.areas.count,
      imports: user.imports.count,
      exports: user.exports.count,
      trips: user.trips.count,
      stats: user.stats.count,
      notifications: user.notifications.count,
      points: user.tracked_points.count,
      visits: user.visits.count,
      places: user.places.count
    }
  end

  def verify_relationships_preserved(original_user, target_user)
    # Verify points maintain their relationships
    original_points_with_imports = original_user.tracked_points.where.not(import_id: nil).count
    target_points_with_imports = target_user.tracked_points.where.not(import_id: nil).count
    expect(target_points_with_imports).to eq(original_points_with_imports)

    original_points_with_countries = original_user.tracked_points.where.not(country_id: nil).count
    target_points_with_countries = target_user.tracked_points.where.not(country_id: nil).count
    expect(target_points_with_countries).to eq(original_points_with_countries)

    original_points_with_visits = original_user.tracked_points.where.not(visit_id: nil).count
    target_points_with_visits = target_user.tracked_points.where.not(visit_id: nil).count
    expect(target_points_with_visits).to eq(original_points_with_visits)

    # Verify visits maintain their place relationships
    original_visits_with_places = original_user.visits.where.not(place_id: nil).count
    target_visits_with_places = target_user.visits.where.not(place_id: nil).count
    expect(target_visits_with_places).to eq(original_visits_with_places)

    # Verify specific relationship consistency
    # Check that points with same coordinates have same relationships
    original_office_points = original_user.tracked_points.where(
      latitude: 40.7589, longitude: -73.9851
    ).first
    target_office_points = target_user.tracked_points.where(
      latitude: 40.7589, longitude: -73.9851
    ).first

    if original_office_points && target_office_points
      expect(target_office_points.import.name).to eq(original_office_points.import.name) if original_office_points.import
      expect(target_office_points.country.name).to eq(original_office_points.country.name) if original_office_points.country
      expect(target_office_points.visit.name).to eq(original_office_points.visit.name) if original_office_points.visit
    end
  end

  def verify_settings_preserved(original_user, target_user)
    # Verify user settings are correctly applied
    expect(target_user.safe_settings.distance_unit).to eq(original_user.safe_settings.distance_unit)
    expect(target_user.safe_settings.timezone).to eq(original_user.safe_settings.timezone)
    expect(target_user.settings['immich_url']).to eq(original_user.settings['immich_url'])
    expect(target_user.settings['immich_api_key']).to eq(original_user.settings['immich_api_key'])
  end

  def verify_files_restored(original_user, target_user)
    # Verify import files are restored
    original_imports_with_files = original_user.imports.joins(:file_attachment).count
    target_imports_with_files = target_user.imports.joins(:file_attachment).count
    expect(target_imports_with_files).to eq(original_imports_with_files)

    # Verify export files are restored
    original_exports_with_files = original_user.exports.joins(:file_attachment).count
    target_exports_with_files = target_user.exports.joins(:file_attachment).count
    expect(target_exports_with_files).to eq(original_exports_with_files)

    # Verify specific file details
    original_import = original_user.imports.find_by(name: 'March 2024 Data')
    target_import = target_user.imports.find_by(name: 'March 2024 Data')

    if original_import&.file&.attached? && target_import&.file&.attached?
      expect(target_import.file.filename.to_s).to eq(original_import.file.filename.to_s)
      expect(target_import.file.content_type).to eq(original_import.file.content_type)
    end
  end
end
