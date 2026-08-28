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

    payload_tempfile = build_export_tempfile
    zipped_tempfile  = Archive::Zipper.wrap(payload_tempfile, entry_name: export.name)

    attach_export_file(zipped_tempfile)

    export.update!(status: :completed, error_message: nil)

    notify_export_finished
  rescue StandardError => e
    export.update!(status: :failed, error_message: e.message)

    notify_export_failed(e)
  ensure
    safe_close = ->(t) { t.close! if t && !t.closed? }
    safe_close.call(payload_tempfile)
    safe_close.call(zipped_tempfile)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :file_format

  def time_framed_points
    points = user.points.where(timestamp: start_at.to_i..end_at.to_i)

    case file_format.to_sym
    when :gpx
      points.select(:id, :lonlat, :altitude, :altitude_decimal, :velocity, :timestamp, :course)
    when :json
      # The point serializer reads the device combo through each point's
      # source; GPX never touches it, and its narrow select carries no
      # source_id for a preload to use.
      points.select(Point.column_names - %w[raw_data]).preload(:source)
    else
      points
    end
  end

  def build_export_tempfile
    case file_format.to_sym
    when :json then Exports::PointGeojsonSerializer.new(time_framed_points).call
    when :gpx  then Exports::PointGpxSerializer.new(time_framed_points, export.name).call
    else raise ArgumentError, I18n.t('services.exports.create.unsupported_file_format', format: file_format)
    end
  end

  def notify_export_finished
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :info,
        title: I18n.t('services.exports.create.export_finished'),
        content: I18n.t('services.exports.create.export_name_successfully_finished', name: export.name)
      ).call
    end
  end

  def notify_export_failed(error)
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('services.exports.create.export_failed'),
        content: I18n.t('services.exports.create.export_name_failed_message_stacktrace_n', name: export.name,
                        message: error.message, backtrace: error.backtrace.join("\n"))
      ).call
    end
  end

  def attach_export_file(zipped_tempfile)
    export.file.attach(
      io: zipped_tempfile,
      filename: "#{export.name}.zip",
      content_type: 'application/zip'
    )
  end
end
