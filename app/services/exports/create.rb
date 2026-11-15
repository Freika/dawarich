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

    report_failure(e)
    notify_export_failed(e)
  ensure
    safe_close = ->(t) { t.close! if t && !t.closed? }
    safe_close.call(payload_tempfile)
    safe_close.call(zipped_tempfile)
  end

  private

  attr_reader :user, :export, :start_at, :end_at, :file_format

  def time_framed_points
    return user.points.none if export.import_scope_unavailable?

    points = user.points.where(timestamp: start_at.to_i..end_at.to_i)
    points = points.where(import_id: export.import_id) if export.import_id.present?

    case file_format.to_sym
    when :gpx
      columns = %w[id lonlat altitude altitude_decimal velocity timestamp course] & Point.column_names
      points.select(*columns)
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
        content: I18n.t('services.exports.create.export_name_successfully_finished', name: export.name),
        action_path: Notifications.paths.exports_path
      ).call
    end
  end

  # The rescue above swallows the error, so this is the only place its stack
  # trace is kept: the log on self-hosted, the error tracker on Cloud.
  def report_failure(error)
    message = "Export #{export.id} failed"
    Rails.logger.error("#{message}: #{error.class}: #{error.message}\n#{error.backtrace&.first(20)&.join("\n")}")
    ExceptionReporter.call(error, message)
  end

  def notify_export_failed(error)
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('services.exports.create.export_failed'),
        content: I18n.t('services.exports.create.export_name_failed_message', name: export.name,
                                                                              message: error.message),
        action_path: Notifications.paths.exports_path
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
