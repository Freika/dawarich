# frozen_string_literal: true

class AddFogOfWarToDefaultSettings < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :settings,
                          from: { meters_between_routes: '1000', minutes_between_routes: '60' },
                          to: { fog_of_war_meters: '100', meters_between_routes: '1000', minutes_between_routes: '60' }
  end
end
