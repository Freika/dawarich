# frozen_string_literal: true

class Shared::AchievementsController < ApplicationController
  layout 'shared'

  before_action :require_feature_enabled
  after_action :allow_embedding, only: :show

  def show
    return redirect_to root_path, alert: I18n.t('achievements.public.not_found') unless shared_progress

    I18n.with_locale(shared_progress.user.locale) do
      @embed = params[:embed] == '1'
      @set = set_presenter
      render :show, layout: @embed ? 'achievement_embed' : 'shared'
    end
  end

  def image
    response.headers['Cache-Control'] = 'private, no-store'
    return head :not_found unless shared_progress

    I18n.with_locale(shared_progress.user.locale) do
      state = exploration.state
      state_digest = Digest::SHA256.hexdigest(state.to_json)
      timezone = shared_progress.user.safe_settings.timezone
      cache_key = "achievements/og/v1/#{shared_progress.id}/#{shared_progress.achievement_key}/" \
                  "#{I18n.locale}/#{timezone}/#{state_digest}"
      png = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        Achievements::OgImage.new(set_presenter).call
      end

      send_data png, type: 'image/png', disposition: 'inline'
    end
  end

  private

  def require_feature_enabled
    return if Flipper.enabled?(:achievements)

    action_name == 'image' ? head(:not_found) : redirect_to(root_path)
  end

  def shared_progress
    @shared_progress ||= Achievements::Progress.find_by(sharing_uuid: params[:uuid], sharing_enabled: true)
    return if @shared_progress&.user.nil?

    @shared_progress if Achievements::Registry.find(@shared_progress.achievement_key)
  end

  def set_presenter
    progress = shared_progress
    Achievements::SetPresenter.new(
      definition: Achievements::Registry.find(progress.achievement_key),
      state: exploration.state,
      sharing: progress,
      timezone: progress.user.safe_settings.timezone
    )
  end

  def exploration
    @exploration ||= Achievements::Progress.exploration_for(shared_progress.user)
  end

  # The badge is meant to be embedded on third-party sites via the modal's
  # iframe snippet; the default SAMEORIGIN header would render it blank there.
  def allow_embedding
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = 'frame-ancestors *'
  end
end
