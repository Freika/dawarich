# frozen_string_literal: true

class CreateTracksFromPoints < ActiveRecord::Migration[8.0]
  def up
    Track.find_each do |track|
      Tracks::CreatePathJob.perform_later(track.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
