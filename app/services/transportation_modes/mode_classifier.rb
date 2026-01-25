# frozen_string_literal: true

module TransportationModes
  # Classifies transportation mode based on speed and acceleration patterns.
  # Uses configurable thresholds and considers acceleration patterns to
  # distinguish between similar-speed modes (e.g., cycling vs running).
  #
  # Speed thresholds are in km/h, acceleration in m/s²
  #
  class ModeClassifier
    # Speed ranges for each mode (km/h)
    # Ranges can overlap - acceleration and other factors help disambiguate
    SPEED_THRESHOLDS = {
      stationary: { min: 0, max: 1 },       # 0-1 km/h
      walking: { min: 1, max: 7 },          # 1-7 km/h
      running: { min: 7, max: 20 },         # 7-20 km/h
      cycling: { min: 7, max: 45 },         # 7-45 km/h (overlaps running/driving)
      driving: { min: 15, max: 220 },       # 15-220 km/h (no speed limit countries)
      motorcycle: { min: 15, max: 220 },    # 15-220 km/h (similar to driving)
      bus: { min: 10, max: 100 },           # 10-100 km/h (urban transit)
      train: { min: 30, max: 350 },         # 30-350 km/h (includes high-speed rail)
      boat: { min: 1, max: 80 },            # 1-80 km/h (varies widely)
      flying: { min: 150, max: 950 }        # 150-950 km/h (commercial aircraft)
    }.freeze

    # Typical acceleration patterns (m/s²)
    # Used to disambiguate modes with similar speeds
    ACCELERATION_PATTERNS = {
      walking: { typical: 0.1, max: 1.5 },      # Smooth, low acceleration
      running: { typical: 0.3, max: 3.0 },      # More variable
      cycling: { typical: 0.2, max: 2.0 },      # Smoother than running
      driving: { typical: 0.5, max: 4.0 },      # Stop-and-go traffic
      motorcycle: { typical: 0.8, max: 5.0 },   # Higher acceleration capability
      bus: { typical: 0.3, max: 2.0 },          # Regular stops, smooth
      train: { typical: 0.1, max: 1.0 },        # Very smooth acceleration
      boat: { typical: 0.1, max: 0.5 },         # Very smooth, slow changes
      flying: { typical: 0.2, max: 2.0 }        # Smooth except takeoff/landing
    }.freeze

    # Classification thresholds for disambiguation
    CLASSIFICATION_THRESHOLDS = {
      # Acceleration thresholds for distinguishing modes (m/s²)
      running_vs_cycling_accel: 0.25,       # Above this suggests running
      cycling_vs_driving_accel: 0.4,        # Above this suggests driving
      motorcycle_accel: 0.6,                # Above this suggests motorcycle
      train_accel: 0.2,                     # Below this suggests train
      bus_accel_range: { min: 0.2, max: 0.4 }, # Range for bus detection

      # Speed boundaries for mode transitions (km/h)
      cycling_max_likely: 35,               # Above this, likely driving not cycling
      train_min: 80,                        # Minimum speed to consider train
      high_speed_boundary: 130,             # Very high speeds: train or autobahn
      flying_threshold: 200                 # Above this, likely flying
    }.freeze

    def initialize(avg_speed_kmh:, max_speed_kmh: nil, avg_acceleration: nil, duration: nil)
      @avg_speed = avg_speed_kmh || 0
      @max_speed = max_speed_kmh || @avg_speed
      @avg_acceleration = avg_acceleration&.abs || 0
      @duration = duration || 0
    end

    def classify
      return :stationary if stationary?
      return :flying if likely_flying?
      return :train if likely_train?

      classify_medium_speed_mode
    end

    def confidence
      return :high if clear_classification?
      return :low if ambiguous_speed_range?

      :medium
    end

    private

    attr_reader :avg_speed, :max_speed, :avg_acceleration, :duration

    def stationary?
      avg_speed <= SPEED_THRESHOLDS[:stationary][:max]
    end

    def likely_flying?
      avg_speed >= SPEED_THRESHOLDS[:flying][:min] && max_speed >= CLASSIFICATION_THRESHOLDS[:flying_threshold]
    end

    def likely_train?
      # Train: high speed with very smooth acceleration
      # Require higher minimum speed to avoid confusion with highway driving
      return false unless avg_speed >= CLASSIFICATION_THRESHOLDS[:train_min] &&
                          avg_speed <= SPEED_THRESHOLDS[:train][:max]

      # Trains have remarkably consistent speed and low acceleration
      avg_acceleration < CLASSIFICATION_THRESHOLDS[:train_accel] && speed_variance_low?
    end

    def classify_medium_speed_mode
      walking_max = SPEED_THRESHOLDS[:walking][:max]
      running_max = SPEED_THRESHOLDS[:running][:max]
      cycling_max = SPEED_THRESHOLDS[:cycling][:max]

      # Walking range: 1-7 km/h
      return :walking if avg_speed <= walking_max && avg_speed > SPEED_THRESHOLDS[:walking][:min]

      # Running vs Cycling: 7-20 km/h
      # Running has more acceleration variability
      if avg_speed > walking_max && avg_speed <= running_max
        return :running if avg_acceleration > CLASSIFICATION_THRESHOLDS[:running_vs_cycling_accel]
        return :cycling if avg_acceleration <= CLASSIFICATION_THRESHOLDS[:running_vs_cycling_accel]
      end

      # Cycling vs Driving: 20-45 km/h
      if avg_speed > running_max && avg_speed <= cycling_max
        # Driving typically has more stop-and-go
        return :driving if avg_acceleration > CLASSIFICATION_THRESHOLDS[:cycling_vs_driving_accel]
        return :cycling if avg_acceleration <= CLASSIFICATION_THRESHOLDS[:cycling_vs_driving_accel] &&
                           avg_speed <= CLASSIFICATION_THRESHOLDS[:cycling_max_likely]

        return :driving
      end

      # Higher speeds: likely driving, motorcycle, bus, or train
      if avg_speed > cycling_max && avg_speed <= CLASSIFICATION_THRESHOLDS[:high_speed_boundary]
        # Bus detection: relatively slow with regular stops
        bus_range = CLASSIFICATION_THRESHOLDS[:bus_accel_range]
        return :bus if avg_acceleration.between?(bus_range[:min], bus_range[:max]) && regular_stop_pattern?

        # Motorcycle vs car: motorcycles can have higher acceleration
        return :motorcycle if avg_acceleration > CLASSIFICATION_THRESHOLDS[:motorcycle_accel]

        return :driving
      end

      # Very high speeds: train or driving on autobahn
      if avg_speed > CLASSIFICATION_THRESHOLDS[:high_speed_boundary] &&
         avg_speed < CLASSIFICATION_THRESHOLDS[:flying_threshold]
        return :train if avg_acceleration < CLASSIFICATION_THRESHOLDS[:train_accel]

        return :driving
      end

      # Default fallback
      :unknown
    end

    def clear_classification?
      # Clear cases: very slow (stationary), very fast (flying), or moderate with consistent patterns
      stationary? || likely_flying? ||
        (avg_speed <= SPEED_THRESHOLDS[:walking][:max] && avg_speed > SPEED_THRESHOLDS[:walking][:min])
    end

    def ambiguous_speed_range?
      # Speeds where multiple modes overlap significantly
      (avg_speed > SPEED_THRESHOLDS[:walking][:max] && avg_speed <= SPEED_THRESHOLDS[:cycling][:max]) ||
        (avg_speed > SPEED_THRESHOLDS[:bus][:max] && avg_speed < CLASSIFICATION_THRESHOLDS[:flying_threshold])
    end

    def speed_variance_low?
      # Without actual variance data, we approximate using max vs avg
      return true if max_speed.nil? || avg_speed.zero?

      (max_speed / avg_speed) < 1.3
    end

    def regular_stop_pattern?
      # Bus detection requires point-level stop analysis which is not available here.
      # This returns false to avoid false positives - buses will be classified as driving.
      # Future enhancement: Pass stop pattern data from MovementAnalyzer.
      false
    end
  end
end
