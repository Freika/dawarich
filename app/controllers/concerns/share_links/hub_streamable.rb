# frozen_string_literal: true

module ShareLinks
  module HubStreamable
    extend ActiveSupport::Concern

    private

    def hub_request?
      params[:hub].present?
    end

    def render_hub_streams(active_tab, errors: nil)
      hub = ShareLinks::HubData.new(current_user, start_date: params[:start_date], end_date: params[:end_date],
                                            import_id: params[:import_id] || params.dig(:shared_link, :import_id))
      @shared_link = SharedLink.new(
        user: current_user, resource_type: :timeline, settings: hub.timeline_settings
      )
      resolved = active_tab == 'shared' && !hub.any_shares? ? 'live' : active_tab

      [
        turbo_stream.update('share-hub-body', partial: 'share_links/hubs/body',
                                              locals: { hub: hub, active_tab: resolved, errors: errors }),
        turbo_stream.replace('live-share-indicator', partial: 'shared/map/share_indicator')
      ]
    end
  end
end
