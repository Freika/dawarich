# frozen_string_literal: true

module Map
  class MaplibreController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!
    layout 'map'

    def index
      @start_at = parsed_start_at
      @end_at = parsed_end_at

      # Status counts shown in the Timeline tab's FILTER section.
      @status_counts = current_user.scoped_visits.group(:status).count
      @suggestions_pending_count = @status_counts['suggested'].to_i

      # Tag chips displayed in the rail; capped so the list doesn't explode.
      @timeline_tags = current_user.tags.order(:name).limit(8)
    end

    private

    def start_at
      return safe_timestamp(params[:start_at]) if params[:start_at].present?

      Time.zone.today.beginning_of_day.to_i
    end

    def end_at
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
