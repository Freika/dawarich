# frozen_string_literal: true

module Tracks
  class ShareLinksController < ApplicationController
    include ShareLinks::Managable

    private

    def load_share_dependencies
      @track = current_user.tracks.find_by(id: params[:track_id])
      return if @track

      render plain: I18n.t('controllers.tracks.share_links.not_found'), status: :not_found
    end

    def active_share_scope
      @track&.shared_links&.where(resource_type: :track)
    end

    def redirect_after_action_path
      new_track_share_link_path(@track)
    end

    def fallback_path
      map_v2_path
    end

    def build_attributes_for_new
      {
        user: current_user,
        resource_type: :track,
        resource_id: @track.id,
        name: track_label
      }
    end

    def build_attributes_for_create
      {
        resource_type: :track,
        resource_id:   @track.id,
        name:          create_params[:name].presence || track_label,
        magic_phrase:  create_params[:magic_phrase].presence,
        expires_at:    expiry_from(create_params[:expires_at]),
        settings:      SharedLink.default_settings_for(:track).merge(extracted_settings)
      }
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :expires_at)
    end

    def track_label
      helpers.track_share_label(@track, current_user.safe_settings.distance_unit)
    end
  end
end
