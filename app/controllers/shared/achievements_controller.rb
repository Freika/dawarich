# frozen_string_literal: true

class Shared::AchievementsController < ApplicationController
  layout 'shared'

  after_action :allow_embedding, only: :show

  def show
    progress = Achievements::Progress.find_by(sharing_uuid: params[:uuid], sharing_enabled: true)
    definition = progress && Achievements::Registry.find(progress.achievement_key)

    if progress.nil? || definition.nil?
      return redirect_to root_path, alert: 'Shared achievement not found or no longer available'
    end

    exploration = Achievements::Progress.exploration_for(progress.user)

    @set = Achievements::SetPresenter.new(
      definition: definition, state: exploration.state, sharing: progress
    )
  end

  private

  # The badge is meant to be embedded on third-party sites via the modal's
  # iframe snippet; the default SAMEORIGIN header would render it blank there.
  def allow_embedding
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = 'frame-ancestors *'
  end
end
