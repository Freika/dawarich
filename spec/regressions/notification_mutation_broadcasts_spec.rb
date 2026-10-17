# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notification mutations across tabs', type: :request do
  let(:user) { create(:user) }
  let(:notification) { create(:notification, user: user) }
  let(:messages) { [] }
  let(:page_messages) { [] }

  before do
    sign_in user
    notification
    @subscription = ActiveSupport::Notifications.subscribe('broadcast.action_cable') do |event|
      case event.payload[:broadcasting]
      when stream_name([user, :notifications]) then messages << event.payload[:message]
      when stream_name([user, :notification_pages]) then page_messages << event.payload[:message]
      end
    end
  end

  after { ActiveSupport::Notifications.unsubscribe(@subscription) }

  def stream_name(streamables)
    Turbo::StreamsChannel.verified_stream_name(Turbo::StreamsChannel.signed_stream_name(streamables))
  end

  def streams
    Nokogiri::HTML.fragment(messages.join).css('turbo-stream')
  end

  def page_actions
    Nokogiri::HTML.fragment(page_messages.join).css('turbo-stream').map { |node| node['action'] }
  end

  it 'refreshes the unread badge after opening a notification' do
    get notification_path(notification)

    expect(notification.reload.read_at).to be_present
    expect(streams.map { |node| node['target'] }).to include('notifications-badge')
    expect(streams.find { |node| node['target'] == 'notifications-badge' }.text).not_to match(/\b1\b/)
  end

  it 'restores an opened enrichment notification when its actual completion job makes it unread' do
    get notification_path(notification)
    messages.clear

    Immich::VerifyEnrichmentJob.perform_now(notification.id, [], 'https://synthetic-immich.test')

    expect(notification.reload).not_to be_read
    insertions = streams.select { |node| node['action'] == 'prepend' && node['target'] == 'notifications-list' }
    expect(insertions.size).to eq(1)
    expect(insertions.first.css("#navbar_notification_#{notification.id}").size).to eq(1)
  end

  it 'removes the list and detail copies after deletion' do
    delete notification_path(notification)

    expect(streams.select { |node| node['action'] == 'remove' }.map { |node| node['target'] })
      .to include("notification_#{notification.id}", "detail_notification_#{notification.id}",
                  "navbar_notification_#{notification.id}")
    expect(streams.map { |node| node['target'] }).to include('notifications-badge')
  end

  it 'invalidates the badge after marking all notifications read' do
    post mark_notifications_as_read_path

    expect(user.notifications.unread).to be_empty
    expect(streams.map { |node| node['target'] }).to include('notifications-badge')
    expect(streams.map { |node| node['action'] }).not_to include('refresh')
    expect(page_actions).to eq(['refresh'])
  end

  it 'subscribes only the notification list to the page refresh stream' do
    signed = Turbo::StreamsChannel.signed_stream_name([user, :notification_pages])

    get notifications_path
    expect(response.body).to include(signed)

    # A refreshed detail page would request a notification that delete-all removed.
    get notification_path(notification)
    expect(response.body).not_to include(signed)
  end

  it 'removes notification copies and refreshes the badge after delete all' do
    post delete_all_notifications_path

    expect(user.notifications).to be_empty
    expect(streams.map { |node| node['target'] }).to include('notifications-badge')
    removal = streams.find { |node| node['action'] == 'remove' }['targets']
    expect(removal).to include('.notification-item', '[id^="notification_"]', '[id^="detail_notification_"]')
    expect(streams.map { |node| node['action'] }).not_to include('refresh')
    expect(page_actions).to eq(['refresh'])
  end

  it 'broadcasts a fixed number of updates when deleting many notifications' do
    create_list(:notification, 5, user: user)
    messages.clear

    post delete_all_notifications_path

    expect(user.notifications).to be_empty
    expect(streams.size).to eq(2)
  end
end
