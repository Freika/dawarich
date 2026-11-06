# frozen_string_literal: true

# Time zone boundaries loaded from lib/assets/timezones.geojson.gz
# (see lib/assets/TIMEZONES_LICENSE.md).
class Timezone < ApplicationRecord
  validates :tzid, :geom, presence: true
end
