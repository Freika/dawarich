# frozen_string_literal: true

class AddPointsRenderingModeToSettings < ActiveRecord::Migration[7.2]
  def up
    User.find_each do |user|
      user.settings = user.settings.merge(points_rendering_mode: 'raw')
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
