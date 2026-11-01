# frozen_string_literal: true

module Points
  # Update-only sensor repair: an absent ID must never recreate deleted history.
  class UpdateMotion
    MAX_UPDATES = 1_000
    MOTIONS = %w[walking running cycling automotive stationary].freeze
    class InvalidUpdates < StandardError; end

    def initialize(user, updates)
      @user = user
      @updates = validate(updates)
    end

    def call
      updated_ids = []
      track_ids = []
      Point.transaction do
        # Stable lock order also serializes repairs with point moves/deletions.
        user.points.where(id: updates.keys).order(:id)
            .select(:id, :motion_data, :track_id, :lock_version).lock.each do |point|
          updated_ids << point.id
          motion_data = (point.motion_data || {}).except('activity').merge('motion' => updates.fetch(point.id))
          next if point.motion_data == motion_data

          point.update_columns(motion_data:, updated_at: Time.current, lock_version: point.lock_version + 1)
          track_ids << point.track_id if point.track_id
        end
        track_ids.uniq.each { |id| TransportationModes::ReclassifyTrackJob.perform_later(id) }
      end
      { updated_ids:, missing_ids: updates.keys - updated_ids }
    end

    private

    attr_reader :user, :updates

    def validate(raw)
      unless raw.is_a?(Array) && raw.any? && raw.size <= MAX_UPDATES
        raise InvalidUpdates, "updates must contain 1 to #{MAX_UPDATES} entries"
      end

      raw.each_with_object({}) do |entry, result|
        unless (entry.is_a?(Hash) || entry.is_a?(ActionController::Parameters)) &&
               entry[:id].is_a?(Integer) && entry[:id].positive? &&
               entry[:motion].is_a?(Array) && entry[:motion].size <= MOTIONS.size &&
               entry[:motion].all? { |motion| MOTIONS.include?(motion) } && !result.key?(entry[:id])
          raise InvalidUpdates,
                'each update requires a unique positive integer id and a supported motion array'
        end

        result[entry[:id]] = entry[:motion].uniq
      end
    end
  end
end
