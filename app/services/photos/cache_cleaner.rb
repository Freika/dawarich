# frozen_string_literal: true

class Photos::CacheCleaner
  attr_reader :user

  def self.call(user)
    new(user).call
  end

  def initialize(user)
    @user = user
  end

  def call
    return unless Rails.cache.respond_to?(:delete_matched)

    Rails.cache.delete_matched("photos_#{user.id}_*")
    Rails.cache.delete_matched("photo_thumbnail_#{user.id}_*")
  end
end
