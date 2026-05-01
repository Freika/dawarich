# frozen_string_literal: true

namespace :imports do
  desc 'Migrate existing imports from `raw_data` to the new file storage'

  task migrate_to_new_storage: :environment do
    Import.find_each do |import|
      import.migrate_to_new_storage
    rescue StandardError => e
      puts "Error migrating import #{import.id}: #{e.message}"
    end
  end
end
