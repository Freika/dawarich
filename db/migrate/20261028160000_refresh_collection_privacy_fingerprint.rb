# frozen_string_literal: true

class RefreshCollectionPrivacyFingerprint < ActiveRecord::Migration[8.1]
  def up
    add_column :achievement_collection_states, :privacy_fingerprint, :string
    execute File.read(Rails.root.join('db/achievement_collections_invalidation.sql'))
  end

  def down
    remove_column :achievement_collection_states, :privacy_fingerprint
  end
end
