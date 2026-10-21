# frozen_string_literal: true

require_relative '../../lib/dawarich/point_revision_schema'

ActiveSupport.on_load(:active_record) do
  ActiveRecord::SchemaDumper.prepend(Dawarich::PointRevisionSchema)
end
