# frozen_string_literal: true

module Families
  module LapseNotice
    KEY = 'plan_lapse_notified_at'

    module_function

    def notified?(user)
      user.settings.dig('family', KEY).present?
    end

    def mark(user)
      write(user, Time.current.iso8601)
    end

    def clear(user)
      return unless notified?(user)

      write(user, nil)
    end

    def write(user, value)
      sql =
        if value.nil?
          ActiveRecord::Base.sanitize_sql_array(
            ["settings = jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}', " \
             "COALESCE(settings->'family', '{}'::jsonb) - ?), updated_at = ?", KEY, Time.current]
          )
        else
          ActiveRecord::Base.sanitize_sql_array(
            ['settings = jsonb_set(' \
             "jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}', " \
             "COALESCE(settings->'family', '{}'::jsonb), true), " \
             "'{family,#{KEY}}', to_jsonb(?::text), true), updated_at = ?", value, Time.current]
          )
        end

      User.where(id: user.id).update_all(sql)
      user.reload
    end
  end
end
