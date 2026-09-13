# frozen_string_literal: true

module Api
  module V1
    module Shared
      class BaseController < ApplicationController
        skip_before_action :verify_authenticity_token, raise: false
        before_action :load_link
        before_action :verify_phrase

        protected

        attr_reader :link

        def ctx
          @ctx ||= SharedLinkContext.new(@link)
        end

        private

        # Matches ApiController: these render JSON for API clients, so the
        # payload must not follow the caller's Accept-Language.
        def switch_locale(&block)
          I18n.with_locale(I18n.default_locale, &block)
        end

        def load_link
          @link = SharedLink.active.find_by(id: params[:id])
          return if @link

          render json: { error: 'not_found' }, status: :not_found
        end

        def verify_phrase
          return if @link.nil?
          return if @link.magic_phrase.blank?
          return if cookies.encrypted["shared_link_#{@link.id}"] == @link.unlock_token

          render json: { error: 'unauthorized' }, status: :unauthorized
        end

        def cache_public_for(seconds)
          return if link&.magic_phrase.present?

          expires_in seconds, public: true
        end

        def privacy_zones
          @privacy_zones ||= ::Users::PrivacyZones.new(link.user).call
        end
      end
    end
  end
end
