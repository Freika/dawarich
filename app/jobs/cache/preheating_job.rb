# frozen_string_literal: true

class Cache::PreheatingJob < ApplicationJob
  queue_as :cache

  def perform
    User.find_each do |user|
      Rails.cache.write(
        "dawarich/user_#{user.id}_years_tracked",
        user.years_tracked,
        expires_in: 1.day
      )
    end
  end
end
