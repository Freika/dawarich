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
      return safe_timestamp(params[:start_at]) if params[:start_at].present?

      TimezoneHelper.today_start_timestamp(user_timezone)
    end

    def end_at
      return safe_timestamp(params[:end_at]) if params[:end_at].present?

      TimezoneHelper.today_end_timestamp(user_timezone)
    end

    def user_timezone
      current_user.timezone.presence || TimezoneHelper::DEFAULT_TIMEZONE
    end

    def parsed_start_at
      Time.zone.at(start_at)
    end

    def parsed_end_at
      Time.zone.at(end_at)
    end
  end
end
