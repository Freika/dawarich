# frozen_string_literal: true

class SetPointsCountryIds < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::StartSettingsPointsCountryIdsJob.perform_later
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
