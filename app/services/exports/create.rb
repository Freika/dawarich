# frozen_string_literal: true

class Exports::Create
  def initialize(export:, start_at:, end_at:)
    @export = export
    @user = export.user
    @start_at = start_at.to_datetime
    @end_at = end_at.to_datetime
  end

  def call
    export.update!(status: :processing)

    pp "====Exporting data for #{user.email} from #{start_at} to #{end_at}"

    points = time_framed_points

    pp "====Exporting #{points.size} points"

    data      = ::ExportSerializer.new(points, user.email).call
    file_path = Rails.root.join('public', 'exports', "#{export.name}.json")

    File.open(file_path, 'w') { |file| file.write(data) }

    export.update!(status: :completed, url: "exports/#{export.name}.json")

    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Export finished',
      content: "Export \"#{export.name}\" successfully finished."
    ).call
  rescue StandardError => e
    Rails.logger.error("====Export failed to create: #{e.message}")

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Export failed',
      content: "Export \"#{export.name}\" failed: #{e.message}"
    ).call

    export.update!(status: :failed)
  end

  private

  attr_reader :user, :export, :start_at, :end_at

  def time_framed_points
    user
      .tracked_points
      .without_raw_data
      .where('timestamp >= ? AND timestamp <= ?', start_at.to_i, end_at.to_i)
  end
end
