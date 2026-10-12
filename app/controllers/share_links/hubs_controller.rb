# frozen_string_literal: true

module ShareLinks
  class HubsController < ApplicationController
    before_action :authenticate_user!

    def show
      @hub = ShareLinks::HubData.new(current_user, start_date: params[:start_date], end_date: params[:end_date])
      @active_tab = resolve_active_tab
      @shared_link = SharedLink.new(
        resource_type: :timeline,
        settings: {
          'start_date' => @hub.default_start_date.iso8601,
          'end_date'   => @hub.default_end_date.iso8601
        }
      )
    end

    private

    def resolve_active_tab
      tab = params[:tab].presence || 'live'
      return 'live' if tab == 'shared' && !@hub.any_shares?

      tab
    end
  end
end
