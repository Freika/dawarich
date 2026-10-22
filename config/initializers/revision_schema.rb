# frozen_string_literal: true

require_relative '../../lib/dawarich/revision_schema'

ActiveSupport.on_load(:active_record) do
  ActiveRecord::SchemaDumper.prepend(Dawarich::RevisionSchema)
end
