# frozen_string_literal: true

# Usage: rake import:big_file['/path/to/file.json','user@email.com']

namespace :import do
  desc 'Accepts a file path and user email and imports the data into the database'

  task :big_file, %i[file_path user_email] => :environment do |_, args|
    Tasks::Imports::GoogleRecords.new(args[:file_path], args[:user_email]).call
  end
end
