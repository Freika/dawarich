# frozen_string_literal: true

# Usage: rake import:big_file['/path/to/file.json','user@email.com']

namespace :import do
  desc 'Accepts a file path and user email and imports the data into the database'

  task :big_file, %i[file_path user_email] => :environment do |_, args|
    user = User.find_by(email: args[:user_email])

    raise 'User not found' unless user

    import = user.imports.create(name: args[:file_path], source: :google_records)

    handler = StreamHandler.new(import.id)

    pp "Importing #{args[:file_path]} for #{user.email}, file size is #{File.size(args[:file_path])}... This might take a while, have patience!"

    File.open(args[:file_path], 'r') do |content|
      Oj.sc_parse(handler, content)
    end

    pp "Imported #{args[:file_path]} for #{user.email} successfully!"
  end
end
