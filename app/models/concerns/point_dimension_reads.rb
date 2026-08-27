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

  included do
    belongs_to :source, class_name: 'PointSource', optional: true

    DIMENSION_ATTRIBUTES.each do |attribute|
      define_method(attribute) do
        return super() unless has_attribute?(:source_id) && source_id

        source ? source.public_send(attribute) : super()
      end
    end
  end
end
