# frozen_string_literal: true

class Photos::CacheCleaner
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    return unless Rails.cache.respond_to?(:delete_matched)

    Rails.cache.delete_matched("photos_#{user.id}_*")
    Rails.cache.delete_matched("photo_thumbnail_#{user.id}_*")
  end

  # Convenience class method for single-line usage
  def self.call(user)
    new(user).call
  end
end
