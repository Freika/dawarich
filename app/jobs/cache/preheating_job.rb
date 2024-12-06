# frozen_string_literal: true

class Cache::PreheatingJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each do |user|
      Rails.cache.fetch("dawarich/user_#{user.id}_years_tracked", expires_in: 1.day) do
        user.years_tracked
      end
    end
  end
end
