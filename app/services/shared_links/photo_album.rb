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

    def shared_link_slug
      link.settings['immich_shared_link_slug'].to_s.presence
    end

    def public_link?
      selected? &&
        link.settings['immich_shared_link_id'].to_s.match?(ID_PATTERN) &&
        shared_link_slug.to_s.match?(ID_PATTERN) &&
        valid_immich_url.present?
    end

    def photo_url(photo_id)
      return unless public_link?
      return unless photo_id.to_s.match?(ID_PATTERN)

      base_url = valid_immich_url
      return if base_url.nil?

      "#{base_url}/s/#{shared_link_slug}/photos/#{photo_id}"
    end

    private

    def valid_immich_url
      uri = URI.parse(link.user.safe_settings.immich_url.to_s)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?

      uri.user = nil
      uri.password = nil
      uri.path = uri.path.to_s.sub(%r{/+\z}, '')
      uri.query = nil
      uri.fragment = nil

      uri.to_s.sub(%r{/+\z}, '')
    rescue URI::InvalidURIError
      nil
    end
  end
end
