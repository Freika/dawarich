# frozen_string_literal: true

# Serves the device/importer combo from point_sources once a row is stamped,
# so the dimension carries production reads before the table rewrite drops
# the legacy columns. A stamped row reads the dimension exclusively — its
# NULLs included; falling back per-attribute would resurrect legacy values
# the writer explicitly cleared. Unstamped rows (opt-out installs, a backfill
# still walking) keep reading the legacy columns, as do partial selects that
# did not load source_id.
module PointDimensionReads
  extend ActiveSupport::Concern

  DIMENSION_ATTRIBUTES = PointSource::COMBO_COLUMNS

  # Only the plain readers are overridden. Enum sugar — suffix predicates,
  # *_before_type_cast, where(battery_status: ...) — still reads the legacy
  # column, which dual-write keeps identical; the table rewrite that drops
  # the columns must re-point those (no app call sites exist today).
  included do
    belongs_to :source, class_name: 'PointSource', optional: true

    DIMENSION_ATTRIBUTES.each do |attribute|
      define_method(attribute) do
        return super() unless has_attribute?(:source_id) && source_id

        # No fallback past this line: the SQL read paths treat any stamped
        # row as dimension-served, and a dangling source_id must not read
        # differently here than there.
        source&.public_send(attribute)
      end
    end
  end
end
