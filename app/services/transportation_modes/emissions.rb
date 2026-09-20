# frozen_string_literal: true

module TransportationModes
  # Per-mode emission scoring for windowed movement features, plus the single
  # source of pipeline tuning constants. All values here are eval-tunable —
  # change numbers, never structure (see spec/eval/transportation_eval_spec.rb).
  module Emissions
    TUNING = {
      window_s: 60, step_s: 30, gap_reset_s: 300,
      accuracy_mask_m: 100.0, accel_mask_mps2: 10.0, sparse_dt_s: 30.0,
      confidence_low: 0.5, confidence_high: 0.8,
      min_track_duration_s: 30, min_auto_sliver_s: 30
    }.freeze

    INFERRED_MODES = %i[stationary walking running cycling driving train flying].freeze
    HINT_ONLY_MODES = %i[bus boat motorcycle].freeze

    # Log-priors: rare modes must earn their classification with clear
    # evidence; kinematic ambiguity defaults toward common modes (train vs
    # highway cruise is THE known tie — without map context, prefer driving).
    MODE_PRIORS = {
      stationary: 0.0, walking: 0.0, running: -0.3, cycling: -0.3,
      driving: 0.0, train: -1.75, flying: -2.5,
      bus: -0.7, boat: -1.5, motorcycle: -1.0
    }.freeze

    # Speeds in km/h. ln: lognormal {center, sigma-of-log}; n: normal {mu, sigma}; w: weight.
    MODE_PROFILES = {
      stationary: { speed_p50: { ln: [0.4, 1.2], w: 1.0 }, speed_p95: { ln: [1.5, 1.5], w: 0.7 },
                    heading_change_rate: nil, motion_variance: nil,
                    stop_fraction: { n: [0.9, 0.15], w: 0.6 } },
      walking: { speed_p50: { ln: [4.5, 0.35], w: 1.0 }, speed_p95: { ln: [6.5, 0.4], w: 0.7 },
                 heading_change_rate: { n: [12.0, 8.0], w: 0.8 },
                 motion_variance: { n: [1.5, 1.5], w: 0.25 },
                 stop_fraction: { n: [0.15, 0.2], w: 0.4 } },
      running: { speed_p50: { ln: [10.0, 0.25], w: 1.0 }, speed_p95: { ln: [14.0, 0.3], w: 0.7 },
                 heading_change_rate: { n: [6.0, 5.0], w: 0.8 },
                 motion_variance: { n: [2.5, 2.0], w: 0.25 },
                 stop_fraction: { n: [0.05, 0.1], w: 0.4 } },
      cycling: { speed_p50: { ln: [17.0, 0.35], w: 1.0 }, speed_p95: { ln: [28.0, 0.35], w: 0.7 },
                 heading_change_rate: { n: [3.0, 3.0], w: 0.8 },
                 motion_variance: { n: [4.0, 3.0], w: 0.25 },
                 stop_fraction: { n: [0.08, 0.15], w: 0.4 } },
      driving: { speed_p50: { ln: [55.0, 0.75], w: 1.0 }, speed_p95: { ln: [110.0, 0.6], w: 0.7 },
                 heading_change_rate: { n: [1.2, 1.5], w: 0.8 },
                 motion_variance: { n: [14.0, 10.0], w: 0.25 },
                 stop_fraction: { n: [0.15, 0.2], w: 0.4 } },
      train: { speed_p50: { ln: [110.0, 0.45], w: 1.0 }, speed_p95: { ln: [170.0, 0.5], w: 0.7 },
               heading_change_rate: { n: [0.3, 0.5], w: 0.8 },
               motion_variance: { n: [8.0, 6.0], w: 0.25 },
               stop_fraction: { n: [0.05, 0.1], w: 0.4 } },
      flying: { speed_p50: { ln: [500.0, 0.5], w: 1.0 }, speed_p95: { ln: [750.0, 0.4], w: 0.7 },
                heading_change_rate: { n: [0.1, 0.3], w: 0.8 },
                motion_variance: { n: [30.0, 25.0], w: 0.25 },
                stop_fraction: { n: [0.01, 0.05], w: 0.4 } },
      boat: { speed_p50: { ln: [15.0, 0.9], w: 1.0 }, speed_p95: nil,
              heading_change_rate: nil, motion_variance: nil, stop_fraction: nil }
    }.freeze

    SPARSE_SIGMA_FACTOR = 1.5
    SPARSE_DROPPED_FEATURES = %i[heading_change_rate motion_variance stop_fraction].freeze

    module_function

    # @param window [Hash] a Windower window
    # @param enabled [Array<Symbol>] user-enabled modes
    # @return [Hash{Symbol => Float}] log-likelihood per candidate mode
    def log_likelihoods(window, enabled:)
      enabled_set = enabled.map(&:to_sym)
      candidates = (INFERRED_MODES & enabled_set) +
                   (window[:hints].keys.map(&:to_sym) & (HINT_ONLY_MODES & enabled_set))

      candidates.uniq.index_with { |mode| score_mode(mode, window) }
    end

    def score_mode(mode, window)
      profile = MODE_PROFILES[mode] || MODE_PROFILES[:driving]
      total = profile.sum { |feature, spec| feature_score(spec, window, feature) }
      total + MODE_PRIORS.fetch(mode, 0.0) +
        (window[:hints][mode] || window[:hints][mode.to_s] || 0.0)
    end

    def feature_score(spec, window, feature)
      return 0.0 if spec.nil?
      return 0.0 if window[:sparse] && SPARSE_DROPPED_FEATURES.include?(feature)

      value = window[feature]
      return 0.0 if value.nil?

      if spec[:ln]
        center, sigma = spec[:ln]
        sigma *= SPARSE_SIGMA_FACTOR if window[:sparse]
        spec[:w] * log_normal_density(value, center, sigma)
      else
        mu, sigma = spec[:n]
        spec[:w] * normal_density(value, mu, sigma)
      end
    end

    def log_normal_density(value, center, sigma)
      x = Math.log(value + 0.1)
      mu = Math.log(center)
      -(((x - mu)**2) / (2 * sigma * sigma)) - Math.log(sigma)
    end

    def normal_density(value, mean, sigma)
      -(((value - mean)**2) / (2 * sigma * sigma)) - Math.log(sigma)
    end
  end
end
