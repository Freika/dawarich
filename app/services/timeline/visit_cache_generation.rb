# frozen_string_literal: true

module Timeline
  class VisitCacheGeneration
    def self.token(user_id, month, timezone)
      ActiveRecord::Base.uncached do
        connection = ActiveRecord::Base.connection
        return unless connection.select_value("SELECT to_regclass('phoenix.epochs')", 'Timeline generation')

        key = "timeline_visit_month/#{user_id}/#{month}/#{timezone}"
        connection.select_value(
          "SELECT token FROM phoenix.epochs WHERE key=#{connection.quote(key)}", 'Timeline generation'
        )
      end
    end
  end
end
