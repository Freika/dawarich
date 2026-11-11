# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::CleanupJob do
  it 'deletes notifications that were read more than 30 days ago' do
    old_read = create(:notification, read_at: 31.days.ago)

    described_class.perform_now

    expect(Notification.exists?(old_read.id)).to be(false)
  end

  it 'keeps notifications read within the last 30 days' do
    recently_read = create(:notification, read_at: 29.days.ago)

    described_class.perform_now

    expect(Notification.exists?(recently_read.id)).to be(true)
  end

  it 'never deletes an unread notification, however old' do
    unread = create(:notification, read_at: nil, created_at: 400.days.ago)

    described_class.perform_now

    expect(Notification.exists?(unread.id)).to be(true)
  end

  it 'runs on the low priority queue' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('low_priority')
  end
end
