# frozen_string_literal: true

class AlignTrackSplitSettingsDefaults < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :settings,
                          from: { 'fog_of_war_meters' => '100', 'meters_between_routes' => '1000',
                                  'minutes_between_routes' => '60' },
                          to: { 'fog_of_war_meters' => '100', 'meters_between_routes' => '500',
                                'minutes_between_routes' => '30' }
  end
end
