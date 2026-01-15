# frozen_string_literal: true

class SetExistingUsersToMapV1 < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      next if user.settings.dig('maps', 'preferred_version') == 'v2'

      user.settings['maps'] ||= {}

      user.settings['maps']['preferred_version'] = 'v1'
      user.save(validate: false)
    end
  end

  def down
    User.find_each do |user|
      user.settings['maps']&.delete('preferred_version')
      user.save(validate: false)
    end
  end
end
