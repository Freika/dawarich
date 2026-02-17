# frozen_string_literal: true

module Map
  class TimelineFeedsController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout false

    def index
      @days = Timeline::DayAssembler.new(
        current_user,
        start_at: parsed_start_at.iso8601,
        end_at: parsed_end_at.iso8601
      ).call
    end

    def track_info
      @track = current_user.tracks.find(params[:id])
    end

    private

    def parsed_start_at
      Time.zone.at(safe_timestamp(params[:start_at]))
    end

    def parsed_end_at
      Time.zone.at(safe_timestamp(params[:end_at]))
    end
  end
end
