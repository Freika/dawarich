# frozen_string_literal: true

module SharedLinks
  class PhotoScope
    PUBLIC_TAG = 'public_share'
    FAMILY_TAG = 'family_share'
    VALID_SCOPES = %w[public family].freeze

    attr_reader :link

    def initialize(link)
      @link = link
    end

    # Returns:
    # - Array<String>: resolved Immich tag IDs
    # - nil: tags could not be resolved; callers must fail closed
    def tag_ids
      tags = Immich::Tags.new(link.user).call
      return nil unless tags.respond_to?(:[])

      required_names.filter_map do |name|
        tag_id(tags[name] || tags[name.to_sym])
      end.then do |ids|
        ids.length == required_names.length ? ids : nil
      end
    rescue StandardError => e
      Rails.logger.error(
        "Shared photo scope resolution failed for link #{link.id}: " \
        "#{e.class} #{e.message}"
      )
      nil
    end

    def scope
      value = link.settings['photo_scope'].to_s
      VALID_SCOPES.include?(value) ? value : 'public'
    end

    private

    def required_names
      scope == 'family' ? [PUBLIC_TAG, FAMILY_TAG] : [PUBLIC_TAG]
    end

    def tag_id(tag)
      return if tag.blank?

      if tag.respond_to?(:[])
        tag['id'].presence || tag[:id].presence
      elsif tag.respond_to?(:id)
        tag.id.presence
      end
    end
  end
end
