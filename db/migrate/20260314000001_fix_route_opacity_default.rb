# frozen_string_literal: true

class FixRouteOpacityDefault < ActiveRecord::Migration[8.0]
  def up
    User.where("(settings->>'route_opacity')::float > 1").find_each do |user|
      old_value = user.settings['route_opacity'].to_f
      new_value = old_value / 100.0
      user.settings = user.settings.merge('route_opacity' => new_value)
      user.save!
    end
  end

  def down
    # No-op: reverting would reintroduce the bug
  end
end
