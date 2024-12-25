# frozen_string_literal: true

class SetReverseGeocodedAtForPoints < ActiveRecord::Migration[7.2]
  def up
    DataMigrations::SetReverseGeocodedAtForPointsJob.perform_later
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
