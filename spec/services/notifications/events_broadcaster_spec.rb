# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::EventsBroadcaster do
  let(:user) { create(:user) }

  before do
    %i[broadcast_prepend_to broadcast_replace_to].each do |method|
      allow(Turbo::StreamsChannel).to receive(method)
    end
  end

  after { described_class.stop }

  it 'does nothing before Phoenix ever migrated' do
    expect(described_class.drain_once).to eq(0)
  end

  it 'turns each event into the navbar prepend and badge replace, and consumes it' do
    connection = ActiveRecord::Base.connection
    connection.execute('CREATE SCHEMA IF NOT EXISTS phoenix')
    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS phoenix.notification_events (
        id bigserial PRIMARY KEY, notification_id bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
      )
    SQL
    notification = Notification.create!(user: user, kind: :info, title: 'Hello', content: 'World')
    connection.execute("INSERT INTO phoenix.notification_events (notification_id) VALUES (#{notification.id})")

    expect(described_class.drain_once).to eq(1)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to)
      .with(
        [user, :notifications],
        target: 'notifications-list',
        partial: 'notifications/navbar_item',
        locals: { notification: }
      ).twice
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(
        [user, :notifications],
        target: 'notifications-badge',
        partial: 'notifications/badge',
        locals: { notification:, count: 1 }
      ).twice
    expect(connection.select_value('SELECT count(*) FROM phoenix.notification_events')).to eq(0)
  end

  it 'skips an event whose notification is gone' do
    phoenix_tables!
    connection = ActiveRecord::Base.connection
    connection.execute('INSERT INTO phoenix.notification_events (notification_id) VALUES (-1)')

    expect(described_class.drain_once).to eq(1)
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
    expect(connection.select_value('SELECT count(*) FROM phoenix.notification_events')).to eq(0)
  end

  it 'start is idempotent and stop joins the thread' do
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(described_class).to receive(:drain_safely) { sleep(0.01) }
    named = -> { Thread.list.count { |thread| thread.name == described_class::THREAD_NAME } }

    2.times { described_class.start }
    expect(named.call).to eq(1)

    described_class.stop
    expect(named.call).to eq(0)
  end
end
