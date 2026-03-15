# frozen_string_literal: true

module Points
  # Extracts transportation-relevant fields into a compact motion_data hash.
  # All methods return string-keyed hashes (matching JSONB round-trip behavior).
  #
  # Source-specific methods are used by individual importers.
  # The `from_raw_data` method auto-detects the source and is used by the backfill job.
  class MotionDataExtractor
    class << self
      # Overland / GeoJSON / Points API — motion, activity, action from properties hash
      def from_overland_properties(properties)
        return {} unless properties

        data = {}
        motion   = properties[:motion] || properties['motion']
        activity = properties[:activity]  || properties['activity']
        action   = properties[:action]    || properties['action']
        data['motion']   = motion   if motion
        data['activity'] = activity if activity
        data['action']   = action   if action
        data
      end

      # Google Phone Takeout — activityRecord.probableActivities and activity
      def from_google_phone_takeout(raw_data)
        return {} unless raw_data

        data = {}
        activity_record = raw_data['activityRecord']
        activities = activity_record['probableActivities'] if activity_record
        data['activityRecord'] = { 'probableActivities' => activities } if activities
        data['activity'] = raw_data['activity'] if raw_data['activity']
        data
      end

      # Google Records.json — activity or activityRecord wrapped as 'activity'
      def from_google_records(location)
        return {} unless location

        activity = location['activity'] || location['activityRecord']
        return {} unless activity

        { 'activity' => activity }
      end

      # Google Semantic History — activities, activityType, travelMode
      def from_google_semantic_history(raw_data)
        return {} unless raw_data

        data = {}
        data['activities']   = raw_data['activities']   if raw_data['activities']
        data['activityType'] = raw_data['activityType'] if raw_data['activityType']
        travel_mode = raw_data.dig('waypointPath', 'travelMode')
        data['travelMode'] = travel_mode if travel_mode
        data
      end

      # OwnTracks — monitoring mode (m) and type
      def from_owntracks(params)
        return {} unless params

        m_val    = params[:m] || params['m']
        type_val = params[:_type] || params['_type']
        return {} unless m_val

        data = { 'm' => m_val }
        data['_type'] = type_val if type_val
        data
      end

      # Auto-detect source from raw_data structure (used by backfill job).
      # Tries each extractor in order, returns the first non-empty result.
      def from_raw_data(raw_data)
        return {} unless raw_data.is_a?(Hash) && raw_data.present?

        from_overland_properties(raw_data['properties']).presence ||
          from_google_all(raw_data).presence ||
          from_owntracks(raw_data).presence ||
          {}
      end

      private

      # Comprehensive Google extraction for backfill — covers all Google formats.
      def from_google_all(raw_data)
        data = {}
        data['activity']       = raw_data['activity']       if raw_data['activity']
        data['activityRecord'] = raw_data['activityRecord'] if raw_data['activityRecord']
        data['activities']     = raw_data['activities']     if raw_data['activities']
        data['activityType']   = raw_data['activityType']   if raw_data['activityType']
        travel_mode = raw_data.dig('waypointPath', 'travelMode')
        data['travelMode'] = travel_mode if travel_mode
        data
      end
    end
  end
end
