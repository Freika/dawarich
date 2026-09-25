# frozen_string_literal: true

# Serves the device/importer combo from point_sources: since Release D the
# dimension is the ONLY home of these attributes — the legacy columns are
# gone. A row without a source (source_id NULL, or a partial select that
# skipped it) reads every combo attribute as nil; there is nothing to fall
# back to, and inventing a fallback would make Ruby reads diverge from the
# SQL paths that join point_sources.
module PointDimensionReads
  extend ActiveSupport::Concern

  DIMENSION_ATTRIBUTES = PointSource::COMBO_COLUMNS

  included do
    belongs_to :source, class_name: 'PointSource', optional: true

    DIMENSION_ATTRIBUTES.each do |attribute|
      define_method(attribute) do
        return unless has_attribute?(:source_id) && source_id

        source&.public_send(attribute)
      end
    end
  end
end
