# frozen_string_literal: true

class Exports::Create
  def initialize(export:, start_at:, end_at:, format: :json)
    @export = export
    @user = export.user
    @start_at = start_at.to_datetime
    @end_at = end_at.to_datetime
    @format = format
  end

  def call
    export.update!(status: :processing)

    Rails.logger.debug "====Exporting data for #{user.email} from #{start_at} to #{end_at}"

    points = time_framed_points

    Rails.logger.debug "====Exporting #{points.size} points"

    data      = ::ExportSerializer.new(points, user.email).call
    file_path = Rails.root.join('public', 'exports', "#{export.name}.#{format}")

    File.open(file_path, 'w') { |file| file.write(data) }

    export.update!(status: :completed, url: "exports/#{export.name}.json")

    create_export_finished_notification
  rescue StandardError => e
    Rails.logger.error("====Export failed to create: #{e.message}")

    create_failed_export_notification(e)

    export.update!(status: :failed)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :format

  def time_framed_points
    user
      .tracked_points
      .where('timestamp >= ? AND timestamp <= ?', start_at.to_i, end_at.to_i)
  end

  def create_export_finished_notification
    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Export finished',
      content: "Export \"#{export.name}\" successfully finished."
    ).call
  end

  def create_failed_export_notification(error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Export failed',
      content: "Export \"#{export.name}\" failed: #{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end

  def process_json_export(points)
  end

  def process_gpx_export(points)
  end
end
