class ExportController < ApplicationController
  before_action :authenticate_user!

  def index
    @export = current_user.export_data
  end

  def download
    first_point_datetime = Time.at(current_user.points.first.timestamp).to_s
    last_point_datetime = Time.at(current_user.points.last.timestamp).to_s
    filename = "dawarich-export-#{first_point_datetime}-#{last_point_datetime}.json".gsub(' ', '_')

    export = current_user.export_data

    send_data export, filename: filename
  end
end
