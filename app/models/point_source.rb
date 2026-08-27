# frozen_string_literal: true

class PointSource < ApplicationRecord
  COMBO_COLUMNS = %w[tracker_id topic ssid bssid connection trigger battery_status inrids in_regions].freeze

  # Mirrors of Point's enums, so a read served through the dimension returns
  # the same labels a legacy-column read did. The mappings must never drift
  # from Point's.
  enum :battery_status, { unknown: 0, unplugged: 1, charging: 2, full: 3, connected_not_charging: 4, discharging: 5 },
       suffix: true
  enum :trigger, {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, suffix: true
  enum :connection, { mobile: 0, wifi: 1, offline: 2, unknown: 4 }, suffix: true

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
