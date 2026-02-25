# frozen_string_literal: true

class Exports::Create
  def initialize(export:)
    @export       = export
    @user         = export.user
    @start_at     = export.start_at
    @end_at       = export.end_at
    @file_format  = export.file_format
  end

  def call
    export.update!(status: :processing)

    tempfile = build_export_tempfile

    attach_export_file(tempfile)

    export.update!(status: :completed, error_message: nil)

    notify_export_finished
  rescue StandardError => e
    export.update!(status: :failed, error_message: e.message)

    notify_export_failed(e)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :file_format

  def time_framed_points
    user
      .points
      .select(Point.column_names - %w[raw_data])
      .where(timestamp: start_at.to_i..end_at.to_i)
  end

  def build_export_tempfile
    case file_format.to_sym
    when :json then Exports::PointGeojsonSerializer.new(time_framed_points).call
    when :gpx  then Exports::PointGpxSerializer.new(time_framed_points, export.name).call
    else raise ArgumentError, "Unsupported file format: #{file_format}"
    end
  end

  def notify_export_finished
    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Export finished',
      content: "Export \"#{export.name}\" successfully finished."
    ).call
  end

  def notify_export_failed(error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Export failed',
      content: "Export \"#{export.name}\" failed: #{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end

  def attach_export_file(tempfile)
    export.file.attach(io: tempfile, filename: export.name, content_type:)
  ensure
    tempfile.close!
  end

  def content_type
    case file_format.to_sym
    when :json then 'application/json'
    when :gpx  then 'application/gpx+xml'
    else raise ArgumentError, "Unsupported file format: #{file_format}"
    end
  end
end
