# frozen_string_literal: true

# Points-domain tile epoch. ⛔ KEY_PREFIX is deployed state: live Redis holds
# keys in this exact format — never change it in a refactor (pinned by spec).
class Points::TileEpoch < TileEpoch
  KEY_PREFIX = 'points:tile_epoch'
end
