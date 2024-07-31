# frozen_string_literal: true

class AddRouteOpacityToSettings < ActiveRecord::Migration[7.1]
  def up
    User.find_each do |user|
      user.settings = user.settings.merge(route_opacity: 20)
      user.save!
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
