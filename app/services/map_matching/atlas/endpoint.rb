# frozen_string_literal: true

require 'uri'

module MapMatching
  module Atlas
    class Endpoint
      include UrlValidatable

      attr_reader :base_url

      def initialize(base_url)
        @base_url = base_url.to_s.strip.sub(%r{/+\z}, '')
      end

      def uri_for(path)
        validate_base_uri!
        base = URI.parse(base_url)
        base.path = "#{base.path.to_s.chomp('/')}#{path}"
        base.query = nil
        base.fragment = nil
        base
      end

      def resolved_ip!
        validate_base_uri!
        resolve_integration_url!(base_url, allow_private: true, allow_credentials: false)
      end

      private

      def validate_base_uri!
        uri = URI.parse(base_url)
        return if base_url.present? && uri.query.blank? && uri.fragment.blank?

        raise UrlValidatable::BlockedUrlError, I18n.t('services.concerns.url_validatable.invalid_format')
      rescue URI::InvalidURIError
        raise UrlValidatable::BlockedUrlError, I18n.t('services.concerns.url_validatable.invalid_format')
      end
    end
  end
end
