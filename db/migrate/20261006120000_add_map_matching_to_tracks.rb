# frozen_string_literal: true

class AddMapMatchingToTracks < ActiveRecord::Migration[8.0]
  def change
    add_column :tracks, :matched_path, :geometry,
               limit: { type: 'multi_line_string', srid: 4326 }
    add_column :tracks, :map_matching_status, :integer
    add_column :tracks, :map_matching_input_digest, :string
    add_column :tracks, :map_matching_data, :jsonb, null: false, default: {}
    add_column :tracks, :map_matched_at, :datetime
  end
end
