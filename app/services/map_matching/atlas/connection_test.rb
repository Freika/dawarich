# frozen_string_literal: true

module MapMatching
  module Atlas
    class ConnectionTest
      def self.call(client: Client.new)
        return [:alert, message(:not_configured)] if DawarichSettings.atlas_url.blank?

        health = client.health
        version = client.version
        return [:alert, message(:routing_unavailable, version: version_label(version))] unless health[:routing] == 'up'

        [:notice, message(:success, version: version_label(version))]
      rescue Client::Error => e
        Rails.logger.warn("event=atlas.connection_test_failed code=#{e.code} status=#{e.status}")
        [:alert, message(:failure, error: e.code)]
      end

      def self.version_label(version)
        [version[:version], version[:revision]&.first(12)].compact.join(' · ')
      end
      private_class_method :version_label

      def self.message(key, **interpolations)
        I18n.t("admin.settings.test_map_matching.#{key}", **interpolations)
      end
      private_class_method :message
    end
  end
end
