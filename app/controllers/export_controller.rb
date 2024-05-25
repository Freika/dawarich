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

    @start_at ||=
      if params[:start_at].nil? && first_point_timestamp.present?
        first_point_timestamp
      elsif params[:start_at].nil?
        1.month.ago.to_i
      else
        Time.zone.parse(params[:start_at]).to_i
      end
  end

  def end_at
    last_point_timestamp = current_user.tracked_points.order(timestamp: :desc)&.last&.timestamp

    @end_at ||=
      if params[:end_at].nil? && last_point_timestamp.present?
        last_point_timestamp
      elsif params[:end_at].nil?
        Time.zone.now.to_i
      else
        Time.zone.parse(params[:end_at]).to_i
      end
  end
end
