# frozen_string_literal: true

class SetDefaultDistanceUnitForUser < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      map_settings = user.settings['maps']

      next if map_settings.try(:[], 'distance_unit')&.in?(%w[km mi])

      if map_settings.blank?
        map_settings = { distance_unit: 'km' }
      else
        map_settings['distance_unit'] = 'km'
      end

      user.settings['maps'] = map_settings
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
