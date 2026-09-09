# frozen_string_literal: true

module Visits
  # The rewritten visit-detection pipeline. Machine visits are a regenerable
  # function of raw points + transportation segments, stamped with VERSION;
  # user edits (confirm, rename, place choice, tombstone) are overlays that
  # survive every re-run.
  module Detection
    # Bump when detection semantics change enough that regenerated output
    # should be distinguishable from previous generations.
    VERSION = 3
  end
end
