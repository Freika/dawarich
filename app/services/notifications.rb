# frozen_string_literal: true

module Notifications
  # Route helpers for call sites: action_path: Notifications.paths.exports_path
  def self.paths
    Rails.application.routes.url_helpers
  end

  class Create
    attr_reader :user, :kind, :title, :content, :operator_only, :action_path

    # operator_only: a background failure only whoever runs the instance can act
    # on. On Cloud that is us and the error tracker already has it, so the user
    # is not told.
    # action_path: the local path the notification opens. An unread notification
    # is kept forever, so point it at a page that cannot disappear (a list or a
    # singleton page), or at a record page whose controller redirects when the
    # record is gone, as Family::LocationRequestsController does.
    def initialize(user:, kind:, title:, content:, operator_only: false, action_path: nil)
      @user     = user
      @kind     = kind
      @title    = title
      # A failure with an empty message must not make its own notification raise.
      @content  = content.presence || title
      @operator_only = operator_only
      @action_path = action_path
    end

    def call
      return if operator_only && !DawarichSettings.self_hosted?
      return if repeated_problem?

      Notification.create!(user:, kind:, title:, content:, action_path:)
    end

    private

    # An identical error or warning that is still unread already says this, so
    # a failure repeating on every job retry is reported once. An info
    # notification is an event of its own (a second export, another batch of
    # achievements) and is always created.
    def repeated_problem?
      kind.to_s != 'info' && user.notifications.unread.exists?(kind:, title:, content:, action_path:)
    end
  end
end
