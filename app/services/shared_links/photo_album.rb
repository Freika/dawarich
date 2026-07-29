# frozen_string_literal: true

module SharedLinks
  class PhotoAlbum
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
  end
end
