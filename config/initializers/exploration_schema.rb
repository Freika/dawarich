# frozen_string_literal: true

# Keep the statement triggers when a database is restored from schema.rb.
# Otherwise fresh installations and test databases would silently miss bulk writes.
module ExplorationSchema
  def tables(stream)
    super
    return unless @connection.data_source_exists?('exploration_states')

    stream.puts '  execute File.read(Rails.root.join("db/exploration_invalidation.sql"))'
  end
end
ActiveSupport.on_load(:active_record) { ActiveRecord::SchemaDumper.prepend(ExplorationSchema) }
