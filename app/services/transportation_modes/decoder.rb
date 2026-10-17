# frozen_string_literal: true

module TransportationModes
  # Log-space Viterbi decoding over window emission scores with hand-set
  # transition penalties, plus forward-backward posteriors for confidence.
  # Chains split by gap_before decode independently.
  #
  # Windows whose points the device is certain about (window[:certain_mode],
  # see HintScorer.certain_mode) are pinned: their emission names only that
  # mode, so Viterbi must pass through it there while uncertain neighbours
  # still decode freely — the transition penalties let them lean toward the
  # pinned mode near the boundary rather than flap. Pinned windows report
  # pinned: true and posterior 1.0.
  class Decoder
    HUBS = %i[stationary walking].freeze

    def self.call(windows, enabled:)
      return [] if windows.empty?

      split_chains(windows).flat_map { |chain| decode_chain(chain, enabled) }
    end

    def self.transition_penalty(from, to)
      return 0.0 if from == to
      return -6.0 if to == :flying || from == :flying
      return -2.5 if HUBS.include?(from) || HUBS.include?(to)
      return -8.0 if [from, to].sort == %i[driving train]

      -5.0
    end

    def self.split_chains(windows)
      chains = []
      current = []
      windows.each do |window|
        if window[:gap_before] && current.any?
          chains << current
          current = []
        end
        current << window
      end
      chains << current if current.any?
      chains
    end

    def self.decode_chain(chain, enabled)
      pins = chain.map { |w| pinned_mode(w, enabled) }
      emissions = chain.each_with_index.map do |w, i|
        pins[i] ? { pins[i] => 0.0 } : Emissions.log_likelihoods(w, enabled: enabled)
      end
      modes = emissions.flat_map(&:keys).uniq
      return chain.map { { mode: :unknown, posterior: 0.0 } } if modes.empty?

      path = viterbi(emissions, modes)
      posteriors = forward_backward(emissions, modes)
      path.each_with_index.map do |mode, i|
        next { mode: mode, posterior: 1.0, pinned: true } if pins[i]

        { mode: mode, posterior: posteriors[i].fetch(mode, 0.0).round(4) }
      end
    end

    # A certain mode pins the window only if the user has it enabled and the
    # pipeline can emit it; otherwise the point's ordinary hint still applies.
    def self.pinned_mode(window, enabled)
      mode = window[:certain_mode]&.to_sym
      return nil unless mode

      emittable = Emissions::INFERRED_MODES + Emissions::HINT_ONLY_MODES
      mode if emittable.include?(mode) && enabled.map(&:to_sym).include?(mode)
    end

    def self.viterbi(emissions, modes)
      scores = {}
      backpointers = []
      modes.each { |m| scores[m] = emission_score(emissions[0], m) }

      (1...emissions.size).each do |i|
        new_scores = {}
        pointers = {}
        modes.each do |to|
          best_from = modes.max_by { |from| scores[from] + transition_penalty(from, to) }
          pointers[to] = best_from
          new_scores[to] = scores[best_from] + transition_penalty(best_from, to) +
                           emission_score(emissions[i], to)
        end
        scores = new_scores
        backpointers << pointers
      end

      last = modes.max_by { |m| scores[m] }
      backpointers.reverse.each_with_object([last]) { |ptrs, path| path.unshift(ptrs[path.first]) }
    end

    def self.forward_backward(emissions, modes)
      n = emissions.size
      forward = Array.new(n) { {} }
      backward = Array.new(n) { {} }

      modes.each { |m| forward[0][m] = emission_score(emissions[0], m) }
      (1...n).each do |i|
        modes.each do |to|
          terms = modes.map { |from| forward[i - 1][from] + transition_penalty(from, to) }
          forward[i][to] = logsumexp(terms) + emission_score(emissions[i], to)
        end
      end

      modes.each { |m| backward[n - 1][m] = 0.0 }
      (n - 2).downto(0) do |i|
        modes.each do |from|
          terms = modes.map do |to|
            transition_penalty(from, to) + emission_score(emissions[i + 1], to) + backward[i + 1][to]
          end
          backward[i][from] = logsumexp(terms)
        end
      end

      (0...n).map do |i|
        joint = modes.index_with { |m| forward[i][m] + backward[i][m] }
        total = logsumexp(joint.values)
        joint.transform_values { |v| Math.exp(v - total) }
      end
    end

    # Missing emission (mode not scored for this window, e.g. hint-only mode
    # without a hint) gets a strong penalty rather than -Infinity so the
    # lattice stays connected.
    def self.emission_score(emission, mode)
      emission.fetch(mode, -1e4)
    end

    def self.logsumexp(values)
      max = values.max
      return max if max.infinite?

      max + Math.log(values.sum { |v| Math.exp(v - max) })
    end
  end
end
