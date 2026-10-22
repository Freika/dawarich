# frozen_string_literal: true

# Tracks-domain tile epoch, independent of the points epoch: track writes
# (generation, merges, deletes, mode reclassification) invalidate track tiles
# without touching cached point tiles, and vice versa.
class Tracks::TileEpoch < TileEpoch
  KEY_PREFIX = 'tracks:tile_epoch'
end
