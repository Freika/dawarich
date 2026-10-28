# frozen_string_literal: true

module AchievementCollectionsSchema
  def tables(stream)
    super
    return unless @connection.data_source_exists?('achievement_collection_states')

    stream.puts '  execute File.read(Rails.root.join("db/achievement_collections_invalidation.sql"))'
  end
end
ActiveSupport.on_load(:active_record) { ActiveRecord::SchemaDumper.prepend(AchievementCollectionsSchema) }
