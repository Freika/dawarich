# frozen_string_literal: true

module SharedLinks
  class PhotoSources
    SOURCES = %w[immich photoprism].freeze

    attr_reader :link

    def initialize(link)
      @link = link
    end

    # Old shared links only have show_photos. Returning nil preserves the
    # original Photos::Search behaviour of using every configured integration.
    def enabled
      return nil unless explicit?

      SOURCES.select { |source| link.settings["show_#{source}"] == true }
    end

    def explicit?
      SOURCES.any? { |source| link.settings.key?("show_#{source}") }
    end
  end
end
