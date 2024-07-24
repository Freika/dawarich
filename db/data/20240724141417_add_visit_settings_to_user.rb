# frozen_string_literal: true

class AddVisitSettingsToUser < ActiveRecord::Migration[7.1]
  def up
    User.find_each do |user|
      user.settings = user.settings.merge(
        time_threshold_minutes: 30,
        merge_threshold_minutes: 15
      )
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
