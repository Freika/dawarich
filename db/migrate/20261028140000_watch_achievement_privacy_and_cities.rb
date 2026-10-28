# frozen_string_literal: true

class WatchAchievementPrivacyAndCities < ActiveRecord::Migration[8.1]
  def up
    execute File.read(Rails.root.join('db/achievement_collections_invalidation.sql'))
  end

  def down
    %w[tags taggings achievement_city_selections].each do |table|
      %w[insert update delete].each do |event|
        execute "DROP TRIGGER IF EXISTS achievement_collections_#{event} ON #{table}"
      end
    end
  end
end
