# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :current_share, :family_api_user

    def connect
      share = verified_live_share

      if (verified_user = env['warden']&.user)
        self.current_user = verified_user
        self.current_share = share
      elsif (api_user = authorized_family_api_user)
        self.family_api_user = api_user
      elsif share
        self.current_user = nil
        self.current_share = share
      else
        reject_unauthorized_connection
      end
    end

    # API credentials only identify the restricted family channel. They do not
    # populate current_user/current_share or grant access to session channels.
    def authorized_family_api_user
      token = request.headers['Authorization'].to_s.match(/\ABearer\s+(\S+)\z/i)&.[](1)
      return if token.blank?

      user = User.find_by(api_key: token)
      return unless user && !user.pending_payment? && user.in_family?
      return unless DawarichSettings.family_feature_available_for?(user)

      user
    end

    # The mobile client has its own 75-second stale-connection timeout. A
    # foreground-only stream needs fewer keepalives than browser Action Cable.
    def beat
      if family_api_user
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last_family_beat && now - @last_family_beat < 30

        @last_family_beat = now
      end
      super
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
