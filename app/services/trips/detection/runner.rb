# frozen_string_literal: true

module Trips
  module Detection
    # One Trip Detection run for one user: reads the visible history, turns it
    # into trip periods and reconciles the user's Detected Trips with them.
    class Runner
      LONG_ABSENCE_KEY = 'trip_detection_long_absence'

      def initialize(user)
        @user = user
      end

      # Returns the trips this run created.
      def call
        runs = user.homes.exists? ? AwayPeriods.new(user).call : []
        result = Candidates.new(runs, time_zone: Time.find_zone!(user.timezone_iana)).call
        record_long_absence(result.long_absence)

        I18n.with_locale(user.locale) { Reconciler.new(user, result.periods).call }
      end

      private

      attr_reader :user

      # One statement on this key only, and only when the value changes, so a
      # settings save running at the same time keeps everything else it wrote.
      def record_long_absence(flag)
        stored = "COALESCE(settings -> '#{LONG_ABSENCE_KEY}' = 'true'::jsonb, FALSE)"
        object = "CASE WHEN jsonb_typeof(settings) = 'object' THEN settings ELSE '{}'::jsonb END"

        User.where(id: user.id).where("#{stored} <> ?", flag).update_all(
          ActiveRecord::Base.sanitize_sql_array(
            ["settings = jsonb_set(#{object}, '{#{LONG_ABSENCE_KEY}}', to_jsonb(?::boolean)), updated_at = ?",
             flag, Time.current]
          )
        )
      end
    end
  end
end
