# frozen_string_literal: true

# Usage: rake import:big_file['/path/to/file.json','user@email.com']

namespace :import do
  desc 'Accepts a file path and user email and imports the data into the database'

  task :big_file, %i[file_path user_email] => :environment do |_, args|
    user = User.find_by(email: args[:user_email])

    raise 'User not found' unless user

    import = user.imports.create(name: args[:file_path], source: :google_records)
    import_id = import.id

    pp "Importing #{args[:file_path]} for #{user.email}, file size is #{File.size(args[:file_path])}... This might take a while, have patience!"

    content = File.read(args[:file_path]); nil
    data = Oj.load(content); nil

    data['locations'].each do |json|
      ImportGoogleTakeoutJob.perform_later(import_id, json.to_json)
    end

    pp "Imported #{args[:file_path]} for #{user.email} successfully! Wait for the processing to finish. You can check the status of the import in the Sidekiq UI (http://<your-dawarich-url>/sidekiq)."
  end
end
