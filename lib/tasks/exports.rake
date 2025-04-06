# frozen_string_literal: true

namespace :exports do
  desc 'Migrate existing exports from file system to the new file storage'

  task migrate_to_new_storage: :environment do
    Export.find_each do |export|
      export.migrate_to_new_storage
    rescue StandardError => e
      puts "Error migrating export #{export.id}: #{e.message}"
    end
  end
end
