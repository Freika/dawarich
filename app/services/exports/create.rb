# frozen_string_literal: true

class Exports::Create
  def initialize(export:)
    @export       = export
    @user         = export.user
    @start_at     = export.start_at
    @end_at       = export.end_at
    @file_format  = export.format
  end

  def call
    ActiveRecord::Base.transaction do
      export.update!(status: :processing)

      points = time_framed_points

      data = points_data(points)

      attach_export_file(data)

      export.update!(status: :completed)

      create_export_finished_notification
    end
  rescue StandardError => e
    create_failed_export_notification(e)

    export.update!(status: :failed)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :file_format

  def time_framed_points
    user
      .tracked_points
      .where(timestamp: start_at.to_i..end_at.to_i)
      .order(timestamp: :asc)
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
    when :gpx  then process_gpx_export(points)
    else raise ArgumentError, "Unsupported file format: #{file_format}"
    end
  end

  def process_geojson_export(points)
    Points::GeojsonSerializer.new(points).call
  end

  def process_gpx_export(points)
    Points::GpxSerializer.new(points, export.name).call
  end

  def attach_export_file(data)
    export.file.attach(io: StringIO.new(data.to_s), filename: export.name, content_type:)
  rescue StandardError => e
    Rails.logger.error("Failed to create export file: #{e.message}")
    raise
  end

  def content_type
    case file_format.to_sym
    when :json then 'application/json'
    when :gpx  then 'application/gpx+xml'
    else raise ArgumentError, "Unsupported file format: #{file_format}"
    end
  end
end
