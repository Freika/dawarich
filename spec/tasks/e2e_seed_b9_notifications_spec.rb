# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_b9_notifications' do
  let!(:demo_user) { User.find_by(email: 'demo@dawarich.app') || create(:user, email: 'demo@dawarich.app') }
  let!(:other_user) { User.find_by(email: 'b9-other@dawarich.test') || create(:user, email: 'b9-other@dawarich.test') }

  it 'creates 22 ordered synthetic notifications and keeps another user separate' do
    Rake::Task['e2e:seed_b9_notifications'].execute

    notifications = demo_user.notifications.where('title LIKE ?', 'B9 fixture%').order(created_at: :desc)
    expect(notifications.count).to eq(22)
    expect(notifications.first.title).to eq('B9 fixture 01')
    expect(notifications.last.title).to eq('B9 fixture 22')
    expect(notifications.unread.count).to eq(19)
    expect(other_user.notifications.where('title LIKE ?', 'B9 fixture%').count).to eq(1)
  end

  it 'replaces its own notifications without touching unrelated ones' do
    unrelated = create(:notification, user: demo_user, title: 'Unrelated')
    Rake::Task['e2e:seed_b9_notifications'].execute
    Rake::Task['e2e:seed_b9_notifications'].execute

    expect(demo_user.notifications.where('title LIKE ?', 'B9 fixture%').count).to eq(22)
    expect(demo_user.notifications).to include(unrelated)
  end
end
