# frozen_string_literal: true

class OwnTracks::Importer
  include Imports::Broadcaster
  include Imports::FileLoader

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

    bulk_insert_points(points_data)
  end

  private

  def bulk_insert_points(batch)
    unique_batch = batch.compact.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations

    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to bulk insert OwnTracks points for user #{user_id}: #{e.message}")

    create_notification("Failed to process OwnTracks data: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'OwnTracks Import Error',
      content: message,
      kind: :error
    )
  end

  def point_valid?(point)
    point['lat'].present? &&
      point['lon'].present? &&
      point['tst'].present?
  end
end
