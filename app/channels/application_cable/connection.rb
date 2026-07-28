# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_share

    def connect
      share = verified_live_share

      if (verified_user = env['warden']&.user)
        self.current_user = verified_user
        self.current_share = share
      elsif share
        self.current_user = nil
        self.current_share = share
      else
        reject_unauthorized_connection
      end
    end

    private

    def verified_live_share
      share_id = request.params[:share_id]
      return if share_id.blank?

      share = SharedLink.active.find_by(id: share_id, resource_type: :live)
      return unless share
      return share if share.magic_phrase.blank?
      return share if cookies.encrypted["shared_link_#{share.id}"] == share.unlock_token

      nil
    end
  end
end
