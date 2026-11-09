# frozen_string_literal: true

module ShareLinks
  class SharesController < ApplicationController
    include ShareLinks::HubStreamable

    before_action :authenticate_user!
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    def edit
      @share = current_user.shared_links.active.find(params[:id])
      render layout: false if turbo_frame_request?
    end

    def update
      @share = current_user.shared_links.active.find(params[:id])
      attrs = params.require(:shared_link).permit(:expires_at, settings: share_setting_keys)
      expires_at = if !attrs.key?(:expires_at)
                     @share.expires_at
                   elsif attrs[:expires_at].present?
                     raw = attrs[:expires_at]
                     zone = Time.find_zone!(current_user.timezone_iana)
                     if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)
                       date = Date.iso8601(raw)
                       zone.local(date.year, date.month, date.day)
                     else
                       raise ArgumentError unless raw.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?\z/)

                       zone.strptime(raw, raw.length == 16 ? '%Y-%m-%dT%H:%M' : '%Y-%m-%dT%H:%M:%S')
                     end
                   end
      settings = attrs.fetch(:settings, {}).to_h.transform_values { |value| ActiveModel::Type::Boolean.new.cast(value) }
      settings = settings.merge(live_freshness_setting) if @share.live?
      if @share.update(expires_at: expires_at, settings: @share.settings.merge(settings))
        render :updated, layout: !turbo_frame_request?
      else
        render :edit, status: :unprocessable_content, layout: !turbo_frame_request?
      end
    rescue ArgumentError
      @share.errors.add(:expires_at, I18n.t('ux_p2.sharing.invalid_expiry'))
      render :edit, status: :unprocessable_content, layout: !turbo_frame_request?
    end

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

    def share_setting_keys
      %i[show_photos show_stats show_route show_countries show_description show_days show_day_notes
         show_map_notes]
    end

    def live_freshness_setting
      key = SharedLink::LIVE_FRESHNESS_KEY
      SharedLink.live_freshness_setting(params.fetch(:shared_link, {}).permit(settings: [key]).dig(:settings, key))
    end

    def not_found
      head :not_found
    end
  end
end
