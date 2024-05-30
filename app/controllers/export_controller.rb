# frozen_string_literal: true

class ExportController < ApplicationController
  before_action :authenticate_user!

  def index
    @start_at = Time.zone.at(start_at)
    @end_at = Time.zone.at(end_at)
  end

  def download
    export = current_user.export_data(start_at:, end_at:)

    send_data export, filename:, type: 'applocation/json', disposition: 'attachment'
  end

  private

  def filename
    first_point_datetime = Time.zone.at(start_at).to_s
    last_point_datetime = Time.zone.at(end_at).to_s

    "dawarich-export-#{first_point_datetime}-#{last_point_datetime}.json".gsub(' ', '_')
  end

  def start_at
    first_point_timestamp = current_user.tracked_points.order(timestamp: :asc)&.first&.timestamp

    @start_at ||= first_point_timestamp || 1.month.ago.to_i
  end

  def end_at
    last_point_timestamp = current_user.tracked_points.order(timestamp: :asc)&.last&.timestamp

    @end_at ||= last_point_timestamp || Time.current.to_i
  end
end
