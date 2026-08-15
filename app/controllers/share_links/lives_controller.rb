# frozen_string_literal: true

module ShareLinks
  class LivesController < ApplicationController
    include ShareLinks::Managable

    private

    def hub_tab
      'live'
    end

    def active_share_scope
      current_user.shared_links.where(resource_type: :live)
    end

    def redirect_after_action_path
      new_share_links_live_path
    end

    def fallback_path
      map_v2_path
    end

    def build_attributes_for_new
      {
        user: current_user,
        resource_type: :live,
        name: I18n.t('controllers.share_links.lives.default_name')
      }
    end

    def build_attributes_for_create
      {
        resource_type: :live,
        resource_id:   nil,
        name:          create_params[:name].presence || I18n.t('controllers.share_links.lives.default_name'),
        magic_phrase:  create_params[:magic_phrase].presence,
        expires_at:    expiry_from(create_params[:expires_at]),
        settings:      SharedLink.default_settings_for(:live).merge(extracted_settings)
      }
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :expires_at)
    end
  end
end
