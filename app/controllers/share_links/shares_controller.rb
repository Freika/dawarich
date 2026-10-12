# frozen_string_literal: true

module ShareLinks
  class SharesController < ApplicationController
    include ShareLinks::HubStreamable

    before_action :authenticate_user!
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    def revoke
      share = current_user.shared_links.find(params[:id])
      share.update!(revoked_at: Time.current)
      SharedLocationChannel.broadcast_to(share, { revoked: true }) if share.resource_type == 'live'

      if hub_request?
        render turbo_stream: render_hub_streams('shared')
      else
        redirect_to map_v2_path
      end
    end

    private

    def not_found
      head :not_found
    end
  end
end
