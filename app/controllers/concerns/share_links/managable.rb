# frozen_string_literal: true

module ShareLinks
  module Managable
    extend ActiveSupport::Concern

    included do
      include ShareLinks::HubStreamable
      before_action :authenticate_user!
      before_action :prepare_share_context
    end

    def new
      @shared_link = SharedLink.new(build_attributes_for_new) unless @share
      render layout: false if turbo_frame_request?
    end

    def create
      @shared_link = current_user.shared_links.build(build_attributes_for_create)

      saved = false
      ActiveRecord::Base.transaction do
        revoke_existing_active_shares!
        saved = @shared_link.save
        raise ActiveRecord::Rollback unless saved
      end

      if saved
        respond_with_hub_or(redirect_after_action_path, active_tab: hub_tab, notice: 'Share link created.')
      elsif hub_request?
        render turbo_stream: render_hub_streams(hub_tab, errors: @shared_link.errors.full_messages),
               status: :unprocessable_content
      else
        @share = nil
        render :new, status: :unprocessable_content, layout: !turbo_frame_request?
      end
    end

    def destroy
      return ensure_share! unless @share

      @share.destroy!
      respond_with_hub_or(redirect_after_action_path, active_tab: hub_tab, notice: 'Share link deleted.')
    end

    def revoke
      return ensure_share! unless @share

      @share.update!(revoked_at: Time.current)
      broadcast_live_share_ended(@share)
      respond_with_hub_or(redirect_after_action_path, active_tab: hub_tab, notice: 'Share link revoked.')
    end

    def regenerate
      return ensure_share! unless @share

      current_user.shared_links.transaction do
        current_user.shared_links.create!(
          resource_type: @share.resource_type,
          resource_id:   @share.resource_id,
          name:          @share.name,
          magic_phrase:  @share.magic_phrase,
          settings:      @share.settings,
          expires_at:    (@share.expires_at if @share.expires_at&.future?)
        )
        broadcast_live_share_ended(@share)
        @share.destroy!
      end
      respond_with_hub_or(redirect_after_action_path, active_tab: hub_tab, notice: 'URL regenerated.')
    end

    def regenerate_phrase
      return ensure_share! unless @share

      @share.update!(magic_phrase: SharedLink::PhraseGenerator.call)
      broadcast_live_share_ended(@share)
      respond_with_hub_or(redirect_after_action_path, active_tab: hub_tab, notice: 'Magic phrase regenerated.')
    end

    private

    def respond_with_hub_or(redirect_path, active_tab:, notice: nil)
      if hub_request?
        render turbo_stream: render_hub_streams(active_tab)
      else
        redirect_to redirect_path, notice: notice
      end
    end

    def hub_tab
      nil
    end

    def prepare_share_context
      load_share_dependencies if respond_to?(:load_share_dependencies, true)
      return if performed?

      load_active_share
    end

    def load_active_share
      @share = active_share_scope&.active&.first
    end

    def ensure_share!
      redirect_to fallback_path, alert: 'No active share link.'
    end

    def revoke_existing_active_shares!
      active_share_scope.active.find_each { |share| broadcast_live_share_ended(share) }
      active_share_scope.active.update_all(revoked_at: Time.current)
    end

    def extracted_settings
      raw = params.fetch(:shared_link, {})[:settings]
      return {} if raw.blank?

      keys = %i[show_photos show_stats show_route show_countries show_description show_days show_day_notes]
      permitted = raw.respond_to?(:permit) ? raw.permit(*keys) : raw.slice(*keys.map(&:to_s))
      permitted.to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    end

    def broadcast_live_share_ended(share)
      return unless share.resource_type == 'live'

      SharedLocationChannel.broadcast_to(share, { revoked: true })
    end

    def expiry_from(raw)
      return nil if raw.blank?

      date = Date.iso8601(raw.to_s)
      zone = Time.find_zone(current_user.timezone_iana) || Time.zone
      zone.local(date.year, date.month, date.day)
    rescue ArgumentError
      nil
    end
  end
end
