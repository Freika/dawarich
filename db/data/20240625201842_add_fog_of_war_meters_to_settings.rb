# frozen_string_literal: true

class AddFogOfWarMetersToSettings < ActiveRecord::Migration[7.1]
  def up
    User.find_each do |user|
      user.settings = user.settings.merge(fog_of_war_meters: 100)
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
