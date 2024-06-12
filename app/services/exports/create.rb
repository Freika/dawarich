# frozen_string_literal: true

class Exports::Create
  def initialize(export:, start_at:, end_at:)
    @export = export
    @user = export.user
    @start_at = start_at
    @end_at = end_at
  end

  def call
    export.update!(status: :processing)

    points    = time_framed_points(start_at, end_at, user)
    data      = ::ExportSerializer.new(points, user.email).call
    file_path = Rails.root.join('public', 'exports', "#{export.name}.json")

    File.open(file_path, 'w') { |file| file.write(data) }

    export.update!(status: :completed, url: "exports/#{export.name}.json")
  rescue StandardError => e
    Rails.logger.error("====Export failed to create: #{e.message}")

    export.update!(status: :failed)
  end

  private

  attr_reader :user, :export, :start_at, :end_at

  def time_framed_points(start_at, end_at, user)
    user.tracked_points.without_raw_data.where('timestamp >= ? AND timestamp <= ?', start_at.to_i, end_at.to_i)
  end
end
