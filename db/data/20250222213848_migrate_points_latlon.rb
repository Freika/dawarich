# frozen_string_literal: true

class MigratePointsLatlon < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      DataMigrations::MigratePointsLatlonJob.perform_later(user.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
