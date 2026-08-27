# frozen_string_literal: true

class PointSource < ApplicationRecord
  COMBO_COLUMNS = %w[tracker_id topic ssid bssid connection trigger battery_status inrids in_regions].freeze

  # Canonical digest of a device/importer combo, computed in SQL so every
  # writer (backfill, ingest) produces byte-identical digests: jsonb normalizes
  # key order and spacing, making md5(jsonb::text) stable. The key list must
  # never change without rewriting every stored digest.
  def self.digest_sql(table_alias)
    pairs = COMBO_COLUMNS.map do |column|
      "'#{column}', #{table_alias}.#{connection.quote_column_name(column)}"
    end

    "md5(jsonb_build_object(#{pairs.join(', ')})::text)"
  end
end
