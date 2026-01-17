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

    def initialize(avg_speed_kmh:, max_speed_kmh: nil, avg_acceleration: nil, duration: nil)
      @avg_speed = avg_speed_kmh || 0
      @max_speed = max_speed_kmh || @avg_speed
      @avg_acceleration = avg_acceleration&.abs || 0
      @duration = duration || 0
    end

    # Returns the most likely transportation mode
    def classify
      return :stationary if stationary?
      return :flying if likely_flying?
      return :train if likely_train?

      # For medium-speed ranges, use acceleration to disambiguate
      classify_medium_speed_mode
    end

    # Returns confidence level (:low, :medium, :high)
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
      # Flying has very distinct speed characteristics
      avg_speed >= 150 && max_speed >= 200
    end

    def likely_train?
      # Train: high speed with very smooth acceleration
      # Require higher minimum speed to avoid confusion with highway driving
      return false unless avg_speed >= 80 && avg_speed <= 350

      # Trains have remarkably consistent speed and low acceleration
      avg_acceleration < 0.2 && speed_variance_low?
    end

    def classify_medium_speed_mode
      # Walking range: 1-7 km/h
      return :walking if avg_speed <= 7 && avg_speed > 1

      # Running vs Cycling: 7-20 km/h
      # Running has more acceleration variability
      if avg_speed > 7 && avg_speed <= 20
        return :running if avg_acceleration > 0.25
        return :cycling if avg_acceleration <= 0.25
      end

      # Cycling vs Driving: 20-45 km/h
      if avg_speed > 20 && avg_speed <= 45
        # Driving typically has more stop-and-go
        return :driving if avg_acceleration > 0.4
        return :cycling if avg_acceleration <= 0.4 && avg_speed <= 35

        return :driving
      end

      # Higher speeds: likely driving, motorcycle, bus, or train
      if avg_speed > 45 && avg_speed <= 130
        # Bus detection: relatively slow with regular stops
        return :bus if avg_acceleration.between?(0.2, 0.4) && regular_stop_pattern?

        # Motorcycle vs car: motorcycles can have higher acceleration
        return :motorcycle if avg_acceleration > 0.6

        return :driving
      end

      # Very high speeds: train or driving on autobahn
      if avg_speed > 130 && avg_speed < 200
        return :train if avg_acceleration < 0.2

        return :driving
      end

      # Default fallback
      :unknown
    end

    def clear_classification?
      # Clear cases: very slow (stationary), very fast (flying), or moderate with consistent patterns
      stationary? || likely_flying? || (avg_speed <= 7 && avg_speed > 1)
    end

    def ambiguous_speed_range?
      # Speeds where multiple modes overlap significantly
      (avg_speed > 7 && avg_speed <= 45) || (avg_speed > 100 && avg_speed < 200)
    end

    def speed_variance_low?
      # Without actual variance data, we approximate using max vs avg
      return true if max_speed.nil? || avg_speed.zero?

      (max_speed / avg_speed) < 1.3
    end

    def regular_stop_pattern?
      # Would need point-level analysis; approximate for now
      # Buses have characteristic stop-and-go every few minutes
      false # Placeholder - could be enhanced with point-level data
    end
  end
end
