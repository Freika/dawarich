# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_b9_notifications' do
  let(:reader) { User.find_by!(email: 'b9-reader@dawarich.test') }
  let(:other_user) { User.find_by!(email: 'b9-other@dawarich.test') }

  around do |example|
    original = ENV['E2E_B9_B11_FIXTURES']
    ENV['E2E_B9_B11_FIXTURES'] = '1'
    example.run
  ensure
    ENV['E2E_B9_B11_FIXTURES'] = original
  end

  it 'refuses to write without explicit fixture opt-in' do
    ENV.delete('E2E_B9_B11_FIXTURES')

    expect { Rake::Task['e2e:seed_b9_notifications'].execute }.to raise_error(SystemExit)
    expect(User.exists?(email: 'b9-reader@dawarich.test')).to be(false)
  end

  it 'refuses to seed in production' do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect { Rake::Task['e2e:seed_b9_notifications'].execute }.to raise_error(SystemExit)
  end

  it 'creates 22 ordered synthetic notifications and keeps another user separate' do
    Rake::Task['e2e:seed_b9_notifications'].execute

    notifications = reader.notifications.where('title LIKE ?', 'B9 fixture%').order(created_at: :desc)
    expect(notifications.count).to eq(22)
    expect(notifications.first.title).to eq('B9 fixture 01')
    expect(notifications.last.title).to eq('B9 fixture 22')
    expect(notifications.unread.count).to eq(19)
    expect(other_user.notifications.where('title LIKE ?', 'B9 fixture%').count).to eq(1)
  end

  it 'replaces its own notifications without touching unrelated ones' do
    Rake::Task['e2e:seed_b9_notifications'].execute
    unrelated = create(:notification, user: reader, title: 'Unrelated')
    Rake::Task['e2e:seed_b9_notifications'].execute

    expect(reader.notifications.where('title LIKE ?', 'B9 fixture%').count).to eq(22)
    expect(reader.notifications).to include(unrelated)
  end
end
