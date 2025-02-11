# frozen_string_literal: true

class Photoprism::CachePreviewToken
  attr_reader :user, :preview_token

  TOKEN_CACHE_KEY = 'dawarich/photoprism_preview_token'

  def initialize(user, preview_token)
    @user = user
    @preview_token = preview_token
  end

  def call
    Rails.cache.write("#{TOKEN_CACHE_KEY}_#{user.id}", preview_token)
  end
end
