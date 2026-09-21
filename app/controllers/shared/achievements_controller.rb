# frozen_string_literal: true

class Shared::AchievementsController < ApplicationController
  layout 'shared'

  before_action :require_feature_enabled
  after_action :allow_embedding, only: :show

  def show
    progress = Achievements::Progress.find_by(sharing_uuid: params[:uuid], sharing_enabled: true)
    definition = progress&.user && Achievements::Registry.find(progress.achievement_key)

    return redirect_to root_path, alert: I18n.t('achievements.public.not_found') if definition.nil?

    I18n.with_locale(progress.user.locale) do
      exploration = Achievements::Progress.exploration_for(progress.user)
      @embed = params[:embed] == '1'

      @set = Achievements::SetPresenter.new(
        definition: definition, state: exploration.state, sharing: progress,
        timezone: progress.user.safe_settings.timezone
      )
      render :show, layout: @embed ? 'achievement_embed' : 'shared'
    end
  end

  private

  def require_feature_enabled
    redirect_to root_path unless Flipper.enabled?(:achievements)
  end

  # The badge is meant to be embedded on third-party sites via the modal's
  # iframe snippet; the default SAMEORIGIN header would render it blank there.
  def allow_embedding
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = 'frame-ancestors *'
  end
end
