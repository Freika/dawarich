# frozen_string_literal: true

class OwnTracks::Importer
  include Imports::Broadcaster

  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import = import
    @user_id = user_id
  end

  def call
    import.file.download do |file|
      parsed_data = OwnTracks::RecParser.new(file).call

      points_data = parsed_data.map do |point|
        OwnTracks::Params.new(point).call.merge(
          import_id: import.id,
          user_id: user_id,
          created_at: Time.current,
          updated_at: Time.current
        )
      end

      bulk_insert_points(points_data)
    end
  end

  private

  def bulk_insert_points(batch)
    unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
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
end
