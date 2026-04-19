# frozen_string_literal: true

module Map
  class MaplibreController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at
    end

    private

    def start_at
      if params[:import_id].present?
        import = current_user.imports.find(params[:import_id])
        return import.points.minimum(:timestamp) || Time.zone.today.beginning_of_day.to_i
      end

      return safe_timestamp(params[:start_at]) if params[:start_at].present?
      Time.zone.today.beginning_of_day.to_i
    end

    def end_at
      if params[:import_id].present?
        import = current_user.imports.find(params[:import_id])
        return import.points.maximum(:timestamp) || Time.zone.today.end_of_day.to_i
      end

      return safe_timestamp(params[:end_at]) if params[:end_at].present?
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
