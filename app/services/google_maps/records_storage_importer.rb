# frozen_string_literal: true

# This class is used to import Google's Records.json file
# via the UI, vs the CLI, which uses the `GoogleMaps::RecordsImporter` class.

class GoogleMaps::RecordsStorageImporter
  include Imports::FileLoader

  BATCH_SIZE = 1000

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user = User.find_by(id: user_id)
    @file_path = file_path
  end

  def call
    process_file_in_batches
  rescue Oj::ParseError, JSON::ParserError => e
    Rails.logger.error("JSON parsing error: #{e.message}")
    raise JSON::ParserError, e.message
  end

  private

  attr_reader :import, :user, :file_path

  def process_file_in_batches
    batch = []
    index = 0
    Imports::JsonStream.new(resolve_file_path, keys: ['locations']).each do |location|
      batch << location
      next unless batch.size >= BATCH_SIZE

      process_batch(batch, index)
      index += BATCH_SIZE
      batch = []
    end
    process_batch(batch, index) unless batch.empty?
  ensure
    cleanup_temp_file
  end

  def process_batch(batch, index)
    GoogleMaps::RecordsImporter.new(import, index).call(batch)
  end
end
