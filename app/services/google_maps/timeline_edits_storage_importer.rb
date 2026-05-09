# frozen_string_literal: true

class GoogleMaps::TimelineEditsStorageImporter
  include Imports::FileLoader

  BATCH_SIZE = 1000

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user = User.find_by(id: user_id)
    @file_path = file_path
  end

  def call
    parsed = load_json_data
    return unless parsed.is_a?(Hash) && parsed['timelineEdits'].is_a?(Array)

    edits = parsed['timelineEdits']
    return if edits.empty?

    process_in_batches(edits)
  rescue Oj::ParseError, JSON::ParserError => e
    Rails.logger.error("JSON parsing error (Timeline Edits): #{e.message}")
    raise
  end

  private

  attr_reader :import, :user, :file_path

  def process_in_batches(edits)
    batch = []
    index = 0

    edits.each do |entry|
      batch << entry
      next unless batch.size >= BATCH_SIZE

      GoogleMaps::TimelineEditsImporter.new(import, index).call(batch)
      index += BATCH_SIZE
      batch = []
    end

    GoogleMaps::TimelineEditsImporter.new(import, index).call(batch) unless batch.empty?
  end
end
