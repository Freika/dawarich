# frozen_string_literal: true

require 'uri'

module InstanceSettings
  class MapMatchingInput
    attr_reader :values, :errors

    def initialize(values)
      @values = values.dup
      @errors = []

      normalize_atlas_url
      validate_atlas_url
      validate_enabled_has_url
    end

    def valid?
      errors.empty?
    end

    private

    def normalize_atlas_url
      return unless values.key?(:atlas_url)

      raw = values[:atlas_url].to_s.strip
      values[:atlas_url] = raw.presence&.sub(%r{/+\z}, '')
    end

    def validate_atlas_url
      return if values[:atlas_url].blank?

      uri = URI.parse(values[:atlas_url])
      valid = uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank? &&
              uri.query.blank? && uri.fragment.blank?
      errors << I18n.t('admin.settings.update.atlas_url_invalid') unless valid
    rescue URI::InvalidURIError
      errors << I18n.t('admin.settings.update.atlas_url_invalid')
    end

    def validate_enabled_has_url
      enabled = values.fetch(:map_matching_enabled) do
        InstanceSettings::Resolver.value(:map_matching_enabled)
      end
      return unless enabled

      atlas_url = values.fetch(:atlas_url) { InstanceSettings::Resolver.value(:atlas_url) }
      errors << I18n.t('admin.settings.update.atlas_url_required') if atlas_url.blank?
    end
  end
end
