# frozen_string_literal: true

module ShareLinks
  module HubStreamable
    extend ActiveSupport::Concern

    private

    def hub_request?
      params[:hub].present?
    end

    def render_hub_streams(active_tab, errors: nil)
      hub = ShareLinks::HubData.new(current_user, start_date: params[:start_date], end_date: params[:end_date])
      @shared_link = SharedLink.new(
        resource_type: :timeline,
        settings: {
          'start_date' => hub.default_start_date.iso8601,
          'end_date'   => hub.default_end_date.iso8601
        }
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
