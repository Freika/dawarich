# frozen_string_literal: true

class Exports::Create
  def initialize(export:, start_at:, end_at:, file_format: :json)
    @export       = export
    @user         = export.user
    @start_at     = start_at.to_datetime
    @end_at       = end_at.to_datetime
    @file_format  = file_format
  end

  def call
    export.update!(status: :processing)

    points = time_framed_points
    data   = points_data(points)

    create_export_file(data)

    export.update!(status: :completed, url: "exports/#{export.name}.#{format}")

    create_export_finished_notification
  rescue StandardError => e
    create_failed_export_notification(e)

    export.update!(status: :failed)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :file_format

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

  def points_data(points)
    case file_format.to_sym
    when :json then process_geojson_export(points)
    when :gpx then process_gpx_export(points)
    else raise ArgumentError, "Unsupported file format: #{file_format}"
    end
  end

  def process_geojson_export(points)
    Points::GeojsonSerializer.new(points).call
  end

  def process_gpx_export(points)
    Points::GpxSerializer.new(points).call
  end

  def create_export_file(data)
    file_path = Rails.root.join('public', 'exports', "#{export.name}.#{file_format}")

    File.open(file_path, 'w') { |file| file.write(data) }
  end
end
