# frozen_string_literal: true

module ShareLinks
  class TimelinesController < ApplicationController
    include ShareLinks::Managable

    private

    def hub_tab
      'timeline'
    end

    def active_share_scope
      current_user.shared_links.where(resource_type: :timeline)
    end

    def redirect_after_action_path
      new_share_links_timeline_path
    end

    def fallback_path
      map_v2_path
    end

    def build_attributes_for_new
      start_date = sanitize_date(params[:start_date]) || 7.days.ago.to_date
      end_date   = sanitize_date(params[:end_date])   || Date.current
      {
        user: current_user,
        resource_type: :timeline,
        name: I18n.t('controllers.share_links.timelines.default_name', start_date: start_date.iso8601,
end_date: end_date.iso8601),
        settings: SharedLink.default_settings_for(:timeline).merge(
          'start_date' => start_date.iso8601,
          'end_date'   => end_date.iso8601
        )
      }
    end

    def sanitize_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def build_attributes_for_create
      {
        resource_type: :timeline,
        resource_id:   nil,
        name:          create_params[:name].presence || default_name_for(create_params),
        magic_phrase:  create_params[:magic_phrase].presence,
        expires_at:    expiry_from(create_params[:expires_at]),
        settings:      SharedLink.default_settings_for(:timeline).merge(
          'start_date' => create_params[:start_date],
          'end_date'   => create_params[:end_date]
        ).merge(extracted_settings)
      }
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :start_date, :end_date, :expires_at)
    end

    def default_name_for(attrs)
      I18n.t(
        'controllers.share_links.timelines.default_name',
        start_date: attrs[:start_date],
        end_date: attrs[:end_date]
      )
    end
  end
end
