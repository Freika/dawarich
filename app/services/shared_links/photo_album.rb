# frozen_string_literal: true

module SharedLinks
  class PhotoAlbum
    ID_PATTERN = /\A[0-9A-Za-z_-]+\z/

    attr_reader :link

    def initialize(link)
      @link = link
    end

    def album_id
      link.settings['photo_album_id'].to_s.presence
    end

    def album_name
      link.settings['photo_album_name'].to_s.presence
    end

    def selected?
      album_id.present?
    end

    def album_url
      immich_url_for('albums', album_id)
    end

    def photo_url(photo_id)
      immich_url_for('photos', photo_id) || album_url
    end

    private

    def immich_url_for(resource, id)
      return unless selected?
      return unless id.to_s.match?(ID_PATTERN)

      base_url = link.user.safe_settings.immich_url.to_s.sub(%r{/+\z}, '')
      uri = URI.parse(base_url)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?

      "#{base_url}/#{resource}/#{id}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
