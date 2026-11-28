# frozen_string_literal: true

module Analytics
  class FirstMapViewsController < ApplicationController
    include SafeTimestampParser

    before_action :authenticate_user!

    def create
      return head :not_found if DawarichSettings.self_hosted?

      period = requested_period
      return render json: { error: 'start_at and end_at must be valid times' }, status: :bad_request unless period

      render json: { status: Analytics::FirstMapView.new(current_user, period).call }
    end

    private

    def requested_period
      start_at = strict_timestamp(params[:start_at].to_s)
      end_at = strict_timestamp(params[:end_at].to_s)
      start_at..end_at if start_at && end_at && start_at <= end_at
    end
  end
end
