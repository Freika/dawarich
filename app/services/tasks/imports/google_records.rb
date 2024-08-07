# frozen_string_literal: true

# This class is named based on Google Takeout's Records.json file,
# the main source of user's location history data.

class Tasks::Imports::GoogleRecords
  def initialize(file_path, user_email)
    @file_path = file_path
    @user = User.find_by(email: user_email)
  end

  def call
    raise 'User not found' unless @user

    import_id = create_import
    log_start
    file_content = read_file
    json_data = Oj.load(file_content)
    schedule_import_jobs(json_data, import_id)
    log_success
  end

  private

  def create_import
    @user.imports.create(name: @file_path, source: :google_records)
  end

  def read_file
    File.read(@file_path)
  end

  def schedule_import_jobs(json_data, import_id)
    json_data['locations'].each do |json|
      ImportGoogleTakeoutJob.perform_later(import_id, json.to_json)
    end
  end

  def log_start
    Rails.logger.debug("Importing #{@file_path} for #{@user.email}, file size is #{File.size(@file_path)}... This might take a while, have patience!")
  end

  def log_success
    Rails.logger.info("Imported #{@file_path} for #{@user.email} successfully! Wait for the processing to finish. You can check the status of the import in the Sidekiq UI (http://<your-dawarich-url>/sidekiq).")
  end
end
