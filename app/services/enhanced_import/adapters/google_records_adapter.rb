# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class GoogleRecordsAdapter < BaseAdapter
      def translate
        enum_for(:translate) unless block_given?

        # Records.json carries no visit / track / place metadata.
        # Wave 3 (per-point activity hints) writes into points.motion_data
        # at point-import time, not here.
      end
    end
  end
end
