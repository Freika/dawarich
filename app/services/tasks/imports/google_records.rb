# frozen_string_literal: true

# This class is named based on Google Takeout's Records.json file,
# the main source of user's location history data.

class Tasks::Imports::GoogleRecords
  BATCH_SIZE = 1000 # Adjust based on your needs

  def initialize(file_path, user_email)
    @file_path = file_path
    @user = User.find_by(email: user_email)
  end

  def call
    raise 'User not found' unless @user

    import_id = create_import
    log_start
    process_file_in_batches(import_id)
    log_success
  rescue Oj::ParseError => e
    Rails.logger.error("JSON parsing error: #{e.message}")
    raise
  end

  private

  def create_import
    @user.imports.create(name: @file_path, source: :google_records).id
  end

  def process_file_in_batches(import_id)
    batch = []

    Oj.load_file(@file_path, mode: :compat) do |record|
      next unless record.is_a?(Hash) && record['locations']

      record['locations'].each do |location|
        batch << prepare_location_data(location, import_id)

        if batch.size >= BATCH_SIZE
          bulk_insert_locations(batch)
          batch = []
        end
      end
    end

    # Process any remaining records
    bulk_insert_locations(batch) if batch.any?
  end

  def prepare_location_data(location, import_id)
    {
      import_id: import_id,
      latitude: location['latitudeE7']&.to_f&. / 1e7,
      longitude: location['longitudeE7']&.to_f&. / 1e7,
      timestamp: Time.at(location['timestampMs'].to_i / 1000),
      accuracy: location['accuracy'],
      source_data: location.to_json,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def bulk_insert_locations(batch)
    Location.upsert_all(
      batch,
      unique_by: %i[import_id timestamp],
      returning: false
    )
  end

  def log_start
    Rails.logger.debug("Importing #{@file_path} for #{@user.email}, file size is #{File.size(@file_path)}... This might take a while, have patience!")
  end

  def log_success
    Rails.logger.info("Imported #{@file_path} for #{@user.email} successfully! Wait for the processing to finish. You can check the status of the import in the Sidekiq UI (http://<your-dawarich-url>/sidekiq).")
  end
end
