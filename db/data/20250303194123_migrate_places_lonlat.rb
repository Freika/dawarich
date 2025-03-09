# frozen_string_literal: true

class MigratePlacesLonlat < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      DataMigrations::MigratePlacesLonlatJob.perform_later(user.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
