# frozen_string_literal: true

# This class is named based on Google Takeout's Records.json file

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
    index = 0

    Oj.load_file(@file_path, mode: :compat) do |record|
      next unless record.is_a?(Hash) && record['locations']

      record['locations'].each do |location|
        batch << location

        next unless batch.size >= BATCH_SIZE

        index += BATCH_SIZE
        Import::GoogleTakeoutJob.perform_later(import_id, Oj.dump(batch), index)
        batch = []
      end
    end

    Import::GoogleTakeoutJob.perform_later(import_id, Oj.dump(batch), index) if batch.any?
  end

  def log_start
    Rails.logger.debug("Importing #{@file_path} for #{@user.email}, file size is #{File.size(@file_path)}... This might take a while, have patience!")
  end

  def log_success
    Rails.logger.info("Imported #{@file_path} for #{@user.email} successfully! Wait for the processing to finish. You can check the status of the import in the Sidekiq UI (http://<your-dawarich-url>/sidekiq).")
  end
end
