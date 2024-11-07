# frozen_string_literal: true

class AddLiveMapEnabledToSettings < ActiveRecord::Migration[7.2]
  def up
    User.find_each do |user|
      user.settings = user.settings.merge(live_map_enabled: false)
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
