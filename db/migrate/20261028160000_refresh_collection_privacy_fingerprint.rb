# frozen_string_literal: true

class RefreshCollectionPrivacyFingerprint < ActiveRecord::Migration[8.1]
  def up
    add_column :achievement_collection_states, :privacy_fingerprint, :string, if_not_exists: true
    execute File.read(Rails.root.join('db/achievement_collections_invalidation.sql'))
  end

  def down
    return unless table_exists?(:achievement_collection_states)

    remove_column :achievement_collection_states, :privacy_fingerprint,
                  if_exists: true
  end
end
