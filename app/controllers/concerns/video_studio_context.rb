# frozen_string_literal: true

# Shared setup for the video studio partial. Themes come from the poster
# studio — the two studios draw the same map style — so this only adds the
# gallery on top.
module VideoStudioContext
  extend ActiveSupport::Concern
  include PosterStudioContext

  private

  def load_video_studio_context
    load_poster_studio_context
    @recent_route_videos = current_user.route_videos.with_attached_file.newest_first.limit(10)
  end
end
