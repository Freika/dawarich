# frozen_string_literal: true

FactoryBot.define do
  factory :user_achievement do
    user
    achievement_key { 'country_de' }
    earned_at { Time.current }
  end
end
