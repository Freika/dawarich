# frozen_string_literal: true

class Notification < ApplicationRecord
  after_create_commit :broadcast_notification
  after_update_commit :broadcast_notification_update
  after_destroy_commit :broadcast_notification_removal

  belongs_to :user

  # A single leading slash, then no backslash, whitespace or control character:
  # browsers read //host and /\host as another site, and strip tabs and newlines
  # before parsing, so "/\t/host" would become //host inside an href.
  ACTION_PATH_FORMAT = %r{\A/(?![/\\])[^\x00-\x20\x7F\\]*\z}

  # Left out of account exports: ids belong to this instance, and action_path
  # names its pages.
  EXPORT_EXCLUDED = %w[user_id id action_path].freeze

  validates :title, :content, :kind, presence: true
  # Only when it is being written, so a row that already holds a bad path can
  # still be marked read.
  validates :action_path, format: { with: ACTION_PATH_FORMAT }, allow_nil: true,
                          if: :will_save_change_to_action_path?

  enum :kind, { info: 0, warning: 1, error: 2 }

  scope :unread, -> { where(read_at: nil).order(created_at: :desc) }

  def read?
    read_at.present?
  end

  # Account import writes rows without validation, so readers use this instead
  # of the raw column.
  def safe_action_path
    action_path if action_path&.match?(ACTION_PATH_FORMAT)
  end

  def update_with_broadcast!(attributes)
    update!(attributes)
  end

  def self.broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :notifications], target: 'notifications-badge',
      partial: 'notifications/badge', locals: { count: user.notifications.unread.count }
    )
  end

  def self.broadcast_read_all_for(user, include_requester: false)
    broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_remove_to([user, :notifications], targets: '.notification-item')
    broadcast_page_refresh_for(user, include_requester:)
  end

  # Targets every list, detail and navbar copy without refreshing other tabs.
  def self.broadcast_delete_all_for(user)
    broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :notifications],
      targets: '.notification-item, [id^="notification_"], [id^="detail_notification_"]'
    )
    broadcast_page_refresh_for(user)
  end

  # Only the notification pages subscribe to this stream: a refresh on the navbar
  # stream would reload every open tab, including maps.
  #
  # Turbo skips a refresh in the tab whose request caused it, because that tab
  # normally reloads through its own redirect. include_requester drops that
  # mark, for a request that answers without reloading the page.
  def self.broadcast_page_refresh_for(user, include_requester: false)
    options = include_requester ? { request_id: nil } : {}
    Turbo::StreamsChannel.broadcast_refresh_to([user, :notification_pages], **options)
  end

  private

  # Broadcasts run at commit, after the code that created the notification has
  # left its I18n.with_locale block, so the recipient's locale is set again here.
  def in_recipient_locale(&)
    I18n.with_locale(user.locale, &)
  end

  def broadcast_notification_update
    self.class.broadcast_badge_for(user)
    in_recipient_locale do
      if read?
        broadcast_remove_to([user, :notifications], target: "navbar_notification_#{id}")
      else
        broadcast_prepend_to([user, :notifications], target: 'notifications-list',
                                                    partial: 'notifications/navbar_item',
                                                    locals: { notification: self })
      end
      [false, true].each do |show_content|
        target = show_content ? "detail_notification_#{id}" : "notification_#{id}"
        broadcast_replace_to([user, :notifications], target: target, partial: 'notifications/notification',
                                                    locals: { notification: self, show_content: show_content })
      end
    end
  end

  def broadcast_notification_removal
    %W[notification_#{id} detail_notification_#{id} navbar_notification_#{id}].each do |target|
      broadcast_remove_to([user, :notifications], target: target)
    end
    self.class.broadcast_badge_for(user)
  end

  def broadcast_notification
    in_recipient_locale do
      broadcast_prepend_to(
        [user, :notifications],
        target: 'notifications-list',
        partial: 'notifications/navbar_item',
        locals: { notification: self }
      )
    end

    self.class.broadcast_badge_for(user)
  end
end
