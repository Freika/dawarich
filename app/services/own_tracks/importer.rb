# frozen_string_literal: true

class OwnTracks::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    file_content = load_file_content
    parsed_data = OwnTracks::RecParser.new(file_content).call

    points_data = parsed_data.map do |point|
      next unless point_valid?(point)

      OwnTracks::Params.new(point).call.merge(
        import_id: import.id,
        user_id: user_id,
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    points_data.compact.each_slice(BATCH_SIZE) do |batch|
      inserted = bulk_insert_points(batch)
      broadcast_import_progress(import, inserted)
    end
  end

  private

  def on_bulk_insert_error(exception)
    ExceptionReporter.call(
      exception, "Failed to bulk insert OwnTracks points for user #{user_id}: #{exception.message}"
    )
  end

  def point_valid?(point)
    point['lat'].present? &&
      point['lon'].present? &&
      point['tst'].present?
  end
end
