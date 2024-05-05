# frozen_string_literal: true

class ExportController < ApplicationController
  before_action :authenticate_user!

  def index
    @export = current_user.export_data
  end

  def download
    export = current_user.export_data

    send_data export, filename:
  end

  private

  def filename
    first_point_datetime = Time.zone.at(current_user.points.first.timestamp).to_s
    last_point_datetime = Time.zone.at(current_user.points.last.timestamp).to_s

    "dawarich-export-#{first_point_datetime}-#{last_point_datetime}.json".gsub(' ', '_')
  end
end
