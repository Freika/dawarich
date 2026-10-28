# frozen_string_literal: true

class TrackCollectionDataset < ActiveRecord::Migration[8.1]
  def change
    add_column :achievement_collection_states, :published_dataset_id, :bigint
  end
end
