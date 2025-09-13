# frozen_string_literal: true

class CreateTracksFromPoints < ActiveRecord::Migration[8.0]
  def up
    # this data migration used to create tracks from existing points. It was deprecated

    nil
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
