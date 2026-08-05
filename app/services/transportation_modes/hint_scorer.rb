# frozen_string_literal: true

module TransportationModes
  # Converts a point's motion_data hint into per-mode log-likelihood boosts.
  # Hints are fused into emission scores — never a hard gate. OwnTracks' `m`
  # field is deliberately ignored: it is the monitoring-mode flag (significant
  # vs move), not a motion state.
  class HintScorer
    GOOGLE_MODE_MAP = {
      'STILL' => :stationary,
      'WALKING' => :walking,
      'ON_FOOT' => :walking,
      'RUNNING' => :running,
      'CYCLING' => :cycling,
      'ON_BICYCLE' => :cycling,
      'IN_VEHICLE' => :driving,
      'IN_ROAD_VEHICLE' => :driving,
      'DRIVING' => :driving,
      'IN_RAIL_VEHICLE' => :train,
      'IN_BUS' => :bus,
      'BUS' => :bus,
      'IN_SUBWAY' => :train,
      'IN_TRAM' => :train,
      'IN_TRAIN' => :train,
      'TRAIN' => :train,
      'IN_FERRY' => :boat,
      'SAILING' => :boat,
      'FLYING' => :flying,
      'IN_AIRPLANE' => :flying,
      'MOTORCYCLING' => :motorcycle
    }.freeze

    OVERLAND_MODE_MAP = {
      'driving' => :driving,
      'automotive' => :driving,
      'walking' => :walking,
      'running' => :running,
      'cycling' => :cycling,
      'stationary' => :stationary
    }.freeze

    # Hints are tracker-level sensor conclusions — when a tracker asserts a
    # mode on every point, that should outweigh ambiguous kinematics (e.g.
    # smooth highway cruise vs train).
    DEFAULT_PROBABILITY = 0.6
    PROBABILITY_SCALE = 8.0
    OVERLAND_BOOST = Math.log(9)

    # Generic vehicle signals (iOS/Android "automotive") cover trains and
    # buses too — expand them so rail stays reachable when kinematics clearly
    # indicate it, while ambiguity still defaults to driving.
    GENERIC_VEHICLE_HINTS = %w[IN_VEHICLE AUTOMOTIVE].freeze
    TRAIN_SHARE_OF_VEHICLE_HINT = 0.7

    def self.call(motion_data)
      return {} unless motion_data.is_a?(Hash) && motion_data.present?

      hints = google_hints(motion_data)
      hints = overland_hints(motion_data) if hints.empty?
      hints
    end

    def self.google_hints(data)
      activities = data.dig('activityRecord', 'probableActivities')
      return from_probable_activities(activities) if activities.is_a?(Array)
      return from_probable_activities(data['activities']) if data['activities'].is_a?(Array)

      type = data['activityType'] || data['travelMode'] || data['activity']
      return {} unless type.is_a?(String)

      mode = GOOGLE_MODE_MAP[type.upcase]
      return {} unless mode

      expand_generic_vehicle({ mode => boost(DEFAULT_PROBABILITY) }, type)
    end

    def self.from_probable_activities(activities)
      hints = {}
      Array(activities).each do |activity|
        next unless activity.is_a?(Hash)

        type = activity['activityType'] || activity['type']
        mode = type && GOOGLE_MODE_MAP[type.to_s.upcase]
        next unless mode

        probability = (activity['probability'] || activity['confidence'] || DEFAULT_PROBABILITY).to_f
        value = boost(probability)
        hints[mode] = [hints[mode], value].compact.max
      end
      strongest_only(hints)
    end

    def self.overland_hints(data)
      motion = data['motion']
      return {} unless motion.is_a?(Array)

      hints = {}
      raw_entries = motion.map { |entry| entry.to_s.downcase }
      raw_entries.each do |entry|
        mode = OVERLAND_MODE_MAP[entry]
        hints[mode] = OVERLAND_BOOST if mode
      end
      generic = raw_entries.find { |e| GENERIC_VEHICLE_HINTS.include?(e.upcase) || e == 'driving' }
      expand_generic_vehicle(strongest_only(hints), generic || '')
    end

    # Keep only the strongest hint: one point reports one dominant activity.
    def self.strongest_only(hints)
      return hints if hints.size <= 1

      hints.max_by { |_mode, value| value }.then { |mode, value| { mode => value } }
    end

    # A :driving hint from a generic vehicle signal also partially supports
    # train — the sensor can't tell a car from a train carriage.
    def self.expand_generic_vehicle(hints, source_type)
      driving_boost = hints[:driving]
      return hints unless driving_boost
      return hints unless generic_vehicle_source?(source_type)

      hints.merge(train: [hints[:train], driving_boost * TRAIN_SHARE_OF_VEHICLE_HINT].compact.max)
    end

    def self.generic_vehicle_source?(source_type)
      normalized = source_type.to_s.upcase
      GENERIC_VEHICLE_HINTS.include?(normalized) || normalized == 'DRIVING' ||
        normalized == 'OTHER_NAVIGATION' || normalized == 'AUTOMOTIVE_NAVIGATION'
    end

    def self.boost(probability)
      Math.log(1 + (PROBABILITY_SCALE * probability.clamp(0.0, 1.0)))
    end
  end
end
