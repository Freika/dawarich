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
      attrs = params.require(:shared_link).permit(:expires_at, settings: SharedLink::SETTING_KEYS)
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
      share.revoke!

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
