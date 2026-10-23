# frozen_string_literal: true

class DataMigrations::UnwrapLegacyImportNamesJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Import.where("name LIKE '%.zip'").includes(file_attachment: :blob).find_each do |import|
      next unless import.file.attached?

      name = Imports::Download.new(import).unwrapped_name
      next if name.nil? || Import.exists?(user_id: import.user_id, name:)

      import.update_columns(name:)
    end
  end
end
