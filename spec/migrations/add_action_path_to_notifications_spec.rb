# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261110120000_add_action_path_to_notifications.rb')

RSpec.describe AddActionPathToNotifications do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  around do |example|
    ActiveRecord::Migration.suppress_messages { example.run }
  end

  after do
    connection.execute('ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_path varchar')
    Notification.reset_column_information
  end

  def roll_back
    migration.migrate(:down)
    Notification.reset_column_information
  end

  def apply
    migration.migrate(:up)
    Notification.reset_column_information
  end

  it 'adds the column again after a rollback' do
    roll_back
    expect(Notification.column_names).not_to include('action_path')

    apply

    column = Notification.columns_hash['action_path']
    expect([column.type, column.null, column.default]).to eq([:string, true, nil])
  end

  it 'can be applied twice and rolled back twice, as a replayed deploy does' do
    expect { 2.times { apply } }.not_to raise_error
    expect(Notification.column_names).to include('action_path')

    expect { 2.times { roll_back } }.not_to raise_error
    expect(Notification.column_names).not_to include('action_path')
  end

  it 'keeps existing notifications, leaving their action_path empty' do
    notification = create(:notification, title: 'Export finished', content: 'done', read_at: 2.days.ago)
    roll_back

    apply

    expect(Notification.find(notification.id)).to have_attributes(
      title: 'Export finished', content: 'done', action_path: nil, read_at: be_present
    )
  end

  it 'drops only its own column on the way down' do
    notification = create(:notification, action_path: '/exports')

    roll_back

    expect(Notification.find(notification.id).title).to eq(notification.title)
  end
end
