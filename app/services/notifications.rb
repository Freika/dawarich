# frozen_string_literal: true

module Notifications
  class Create
    attr_reader :user, :kind, :title, :content, :deduplicate

    # deduplicate: skip when an identical notification is still unread, so a
    # failure that repeats on every job retry is reported once.
    def initialize(user:, kind:, title:, content:, deduplicate: false)
      @user     = user
      @kind     = kind
      @title    = title
      @content  = content
      @deduplicate = deduplicate
    end

    def call
      return if deduplicate && user.notifications.unread.exists?(kind:, title:, content:)

      Notification.create!(user:, kind:, title:, content:)
    end
  end
end
