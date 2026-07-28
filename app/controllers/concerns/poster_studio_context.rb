# frozen_string_literal: true

module PosterStudioContext
  extend ActiveSupport::Concern

  private

  def load_poster_studio_context
    @poster_themes = local_poster_themes
    @recent_posters = current_user.posters.with_attached_image.order(created_at: :desc).limit(10)
  end

  # Poster theme tokens are vendored under public/poster_themes and read
  # directly — they also power the map's custom-colour editor.
  def local_poster_themes
    Rails.cache.fetch('local_poster_themes', expires_in: 1.hour) do
      Dir.glob(Rails.root.join('public/poster_themes/*.json')).sort.filter_map do |path|
        data = JSON.parse(File.read(path))
        data.merge('key' => File.basename(path, '.json'), 'route' => data['route'].presence || '#FF3B30')
      rescue JSON::ParserError
        nil
      end
    end
  end
end
