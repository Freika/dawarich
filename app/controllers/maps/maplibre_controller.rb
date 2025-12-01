module Maps
  class MaplibreController < ApplicationController
    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at
    end

  private

  def start_at
    return Time.zone.parse(params[:start_at]).to_i if params[:start_at].present?

    Time.zone.today.beginning_of_day.to_i
  end

  def end_at
    return Time.zone.parse(params[:end_at]).to_i if params[:end_at].present?

    Time.zone.today.end_of_day.to_i
  end

  def parsed_start_at
    Time.zone.at(start_at)
  end

  def parsed_end_at
    Time.zone.at(end_at)
  end
  end
end
