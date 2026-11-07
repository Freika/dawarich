# frozen_string_literal: true

module ShareLinks
  class HubsController < ApplicationController
    before_action :authenticate_user!

    def show
      @hub = ShareLinks::HubData.new(current_user, start_date: params[:start_date], end_date: params[:end_date],
                                            import_id: params[:import_id])
      @active_tab = resolve_active_tab
      @shared_link = SharedLink.new(
        user: current_user, resource_type: :timeline, settings: @hub.timeline_settings
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
