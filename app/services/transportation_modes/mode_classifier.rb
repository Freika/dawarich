# frozen_string_literal: true

module TransportationModes
  # Classifies transportation mode based on speed and acceleration patterns.
  # Uses configurable thresholds and considers acceleration patterns to
  # distinguish between similar-speed modes (e.g., cycling vs running).
  #
  # Speed thresholds are in km/h, acceleration in m/s²
  #
  # Supports user-configurable thresholds via the user_thresholds parameter.
  # When provided, user thresholds override the default values.
  #
  class ModeClassifier
    # Default speed ranges for each mode (km/h)
    # Ranges can overlap - acceleration and other factors help disambiguate
    DEFAULT_SPEED_THRESHOLDS = {
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

    # Default classification thresholds for disambiguation
    DEFAULT_CLASSIFICATION_THRESHOLDS = {
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

    # @param avg_speed_kmh [Float] Average speed in km/h
    # @param max_speed_kmh [Float, nil] Maximum speed in km/h
    # @param avg_acceleration [Float, nil] Average acceleration in m/s²
    # @param duration [Integer, nil] Duration in seconds
    # @param user_thresholds [Hash, nil] User-configured thresholds from settings
    #   Expected keys (from SafeSettings#transportation_thresholds):
    #   - 'walking_max_speed' => 7
    #   - 'cycling_max_speed' => 45
    #   - 'driving_max_speed' => 220
    #   - 'flying_min_speed' => 150
    # @param user_expert_thresholds [Hash, nil] Expert thresholds from settings
    #   Expected keys (from SafeSettings#transportation_expert_thresholds):
    #   - 'stationary_max_speed' => 1
    #   - 'running_vs_cycling_accel' => 0.25
    #   - 'cycling_vs_driving_accel' => 0.4
    #   - 'train_min_speed' => 80
    def initialize(avg_speed_kmh:, max_speed_kmh: nil, avg_acceleration: nil, duration: nil,
                   user_thresholds: nil, user_expert_thresholds: nil)
      @avg_speed = avg_speed_kmh || 0
      @max_speed = max_speed_kmh || @avg_speed
      @avg_acceleration = avg_acceleration&.abs || 0
      @duration = duration || 0
      @user_thresholds = normalize_hash_keys(user_thresholds)
      @user_expert_thresholds = normalize_hash_keys(user_expert_thresholds)

      # Build effective thresholds by merging user settings with defaults
      @speed_thresholds = build_speed_thresholds
      @classification_thresholds = build_classification_thresholds
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

    attr_reader :avg_speed, :max_speed, :avg_acceleration, :duration,
                :speed_thresholds, :classification_thresholds

    def normalize_hash_keys(hash)
      return {} if hash.nil?

      hash.transform_keys(&:to_s)
    end

    def build_speed_thresholds
      thresholds = DEFAULT_SPEED_THRESHOLDS.deep_dup

      # Apply user thresholds (max speeds define the upper bound of each mode)
      if @user_thresholds['walking_max_speed']
        thresholds[:walking][:max] = @user_thresholds['walking_max_speed'].to_f
        thresholds[:running][:min] = @user_thresholds['walking_max_speed'].to_f
      end

      thresholds[:cycling][:max] = @user_thresholds['cycling_max_speed'].to_f if @user_thresholds['cycling_max_speed']

      if @user_thresholds['driving_max_speed']
        thresholds[:driving][:max] = @user_thresholds['driving_max_speed'].to_f
        thresholds[:motorcycle][:max] = @user_thresholds['driving_max_speed'].to_f
      end

      thresholds[:flying][:min] = @user_thresholds['flying_min_speed'].to_f if @user_thresholds['flying_min_speed']

      # Apply expert thresholds
      if @user_expert_thresholds['stationary_max_speed']
        thresholds[:stationary][:max] = @user_expert_thresholds['stationary_max_speed'].to_f
        thresholds[:walking][:min] = @user_expert_thresholds['stationary_max_speed'].to_f
      end

      thresholds
    end

    def build_classification_thresholds
      thresholds = DEFAULT_CLASSIFICATION_THRESHOLDS.deep_dup

      # Apply expert thresholds
      if @user_expert_thresholds['running_vs_cycling_accel']
        thresholds[:running_vs_cycling_accel] = @user_expert_thresholds['running_vs_cycling_accel'].to_f
      end

      if @user_expert_thresholds['cycling_vs_driving_accel']
        thresholds[:cycling_vs_driving_accel] = @user_expert_thresholds['cycling_vs_driving_accel'].to_f
      end

      if @user_expert_thresholds['train_min_speed']
        thresholds[:train_min] = @user_expert_thresholds['train_min_speed'].to_f
      end

      # flying_threshold derived from flying_min_speed if provided
      if @user_thresholds['flying_min_speed']
        thresholds[:flying_threshold] = @user_thresholds['flying_min_speed'].to_f + 50
      end

      thresholds
    end

    def stationary?
      avg_speed <= speed_thresholds[:stationary][:max]
    end

    def likely_flying?
      avg_speed >= speed_thresholds[:flying][:min] && max_speed >= classification_thresholds[:flying_threshold]
    end

    def likely_train?
      # Train: high speed with very smooth acceleration
      # Require higher minimum speed to avoid confusion with highway driving
      return false unless avg_speed >= classification_thresholds[:train_min] &&
                          avg_speed <= speed_thresholds[:train][:max]

      # Trains have remarkably consistent speed and low acceleration
      avg_acceleration < classification_thresholds[:train_accel] && speed_variance_low?
    end

    def classify_medium_speed_mode
      walking_max = speed_thresholds[:walking][:max]
      running_max = speed_thresholds[:running][:max]
      cycling_max = speed_thresholds[:cycling][:max]

      # Walking range: 1-7 km/h (configurable)
      return :walking if avg_speed <= walking_max && avg_speed > speed_thresholds[:walking][:min]

      # Running vs Cycling: 7-20 km/h
      # Running has more acceleration variability
      if avg_speed > walking_max && avg_speed <= running_max
        return :running if avg_acceleration > classification_thresholds[:running_vs_cycling_accel]
        return :cycling if avg_acceleration <= classification_thresholds[:running_vs_cycling_accel]
      end

      # Cycling vs Driving: 20-45 km/h (configurable)
      if avg_speed > running_max && avg_speed <= cycling_max
        # Driving typically has more stop-and-go
        return :driving if avg_acceleration > classification_thresholds[:cycling_vs_driving_accel]
        return :cycling if avg_acceleration <= classification_thresholds[:cycling_vs_driving_accel] &&
                           avg_speed <= classification_thresholds[:cycling_max_likely]

        return :driving
      end

      # Higher speeds: likely driving, motorcycle, bus, or train
      if avg_speed > cycling_max && avg_speed <= classification_thresholds[:high_speed_boundary]
        # Bus detection: relatively slow with regular stops
        bus_range = classification_thresholds[:bus_accel_range]
        return :bus if avg_acceleration.between?(bus_range[:min], bus_range[:max]) && regular_stop_pattern?

        # Motorcycle vs car: motorcycles can have higher acceleration
        return :motorcycle if avg_acceleration > classification_thresholds[:motorcycle_accel]

        return :driving
      end

      # Very high speeds: train or driving on autobahn
      if avg_speed > classification_thresholds[:high_speed_boundary] &&
         avg_speed < classification_thresholds[:flying_threshold]
        return :train if avg_acceleration < classification_thresholds[:train_accel]

        return :driving
      end

      # Default fallback
      :unknown
    end

    def clear_classification?
      # Clear cases: very slow (stationary), very fast (flying), or moderate with consistent patterns
      stationary? || likely_flying? ||
        (avg_speed <= speed_thresholds[:walking][:max] && avg_speed > speed_thresholds[:walking][:min])
    end

    def ambiguous_speed_range?
      # Speeds where multiple modes overlap significantly
      (avg_speed > speed_thresholds[:walking][:max] && avg_speed <= speed_thresholds[:cycling][:max]) ||
        (avg_speed > speed_thresholds[:bus][:max] && avg_speed < classification_thresholds[:flying_threshold])
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
