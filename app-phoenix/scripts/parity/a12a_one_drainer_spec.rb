# frozen_string_literal: true

require 'rails_helper'
require_relative 'a12a_fixture_support'

RSpec.describe 'Phoenix parity: exactly one runtime drains the A12a event queues', type: :request do
  self.use_transactional_tests = false

  def fx = A12aFixtureSupport
  def user_ids = [971_251, 971_252]

  def cleanup!
    User.unscoped.where(id: user_ids).update_all(deleted_at: nil)
    User.where(id: user_ids).find_each { |user| Users::Destroy.new(user).call }
  end

  def seed!
    owner = create(:user, id: 971_251, email: 'a12a-drain-owner@dawarich.test')
    gone = create(:user, id: 971_252, email: 'a12a-drain-gone@dawarich.test')
    kept = create(:notification, id: 971_261, user: owner, title: 'A12a kept', content: 'A12a')
    lost = create(:notification, id: 971_262, user: gone, title: 'A12a lost', content: 'A12a')
    gone.update_columns(deleted_at: Time.current)
    trip = create(:trip, id: 971_271, user: owner, name: 'A12a drain', last_recalculated_at: nil)
    [owner, kept, lost, trip]
  end

  def queue!(kept, lost, trip)
    connection = ActiveRecord::Base.connection
    [lost, kept].each do |notification|
      connection.execute("INSERT INTO phoenix.notification_events (notification_id) VALUES (#{notification.id})")
    end
    [['path', false], ['distance', false], ['countries', false], ['finished', true]].each do |kind, failed|
      connection.execute(
        'INSERT INTO phoenix.trip_events (trip_id, kind, distance_unit, failed, created_at) ' \
        "VALUES (#{trip.id}, '#{kind}', 'km', #{failed}, now())"
      )
    end
  end

  def queued
    connection = ActiveRecord::Base.connection
    %w[notification_events trip_events].sum { |table| connection.select_value("SELECT count(*) FROM phoenix.#{table}") }
  end

  def sidekiq_server_hooks
    blocks = []
    allow(Sidekiq).to receive(:configure_server) { |&block| blocks << block }
    allow(Sidekiq).to receive(:configure_client)
    allow(Sidekiq).to receive(:server?).and_return(false)
    load Rails.root.join('config/initializers/sidekiq.rb')
    config = Sidekiq::Config.new
    blocks.each { |block| block.call(config) }
    config[:lifecycle_events]
  end

  def start_rails_drainers(hooks)
    before = Thread.list
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
    hooks[:startup].each(&:call)
    allow(Rails).to receive(:env).and_call_original
    Thread.list - before
  end

  def stop_rails_drainers(hooks, threads)
    hooks[:shutdown].each(&:call)
    threads.each(&:kill).each(&:join)
  end

  def phoenix_drain
    db = ActiveRecord::Base.connection_db_config.configuration_hash
    env = { 'DATABASE_PORT' => db[:port].to_s, 'DATABASE_USERNAME' => db[:username].to_s,
            'DATABASE_PASSWORD' => db[:password].to_s }
    fx.phoenix(<<~ELIXIR.squish, env)
      {:ok, _} = Application.ensure_all_started(:ecto_sql);
      {:ok, _} = Application.ensure_all_started(:redix);
      {:ok, _} = Dawarich.Repo.start_link(database: "#{db[:database]}", pool: DBConnection.ConnectionPool, pool_size: 2);
      {:ok, _} = Redix.start_link(Application.fetch_env!(:dawarich, :redis)[:url], name: Dawarich.Redis);
      IO.puts(Jason.encode!(%{"drained" => Dawarich.Cable.TurboEvents.drain(Dawarich.Repo, Dawarich.Repo)}))
    ELIXIR
  end

  def heard(queue)
    out = []
    while (message = queue.pop(timeout: 1))
      out << message
    end
    out
  end

  def wrapper(payload) = JSON.parse(payload)[/\A<turbo-stream[^>]*>/]

  it 'publishes every queued event once, from Phoenix, as ED-A12A-5 and ED-A12A-6 describe' do
    created_schema = !ActiveRecord::Base.connection.select_value("SELECT to_regnamespace('phoenix') IS NOT NULL")
    phoenix_tables!
    cleanup!
    owner, kept, lost, trip = seed!
    queue!(kept, lost, trip)
    queue, capture = fx.capture
    hooks = sidekiq_server_hooks
    threads = start_rails_drainers(hooks)
    expect(phoenix_drain).to eq('drained' => 6)
    published = heard(queue)

    notifications = "#{owner.to_gid_param}:notifications"
    expect(published.map(&:first)).to eq([notifications, notifications, trip.to_gid_param, trip.to_gid_param])
    expect(published.map { |_, payload| wrapper(payload) }).to eq(
      ['<turbo-stream action="prepend" target="notifications-list">',
       '<turbo-stream action="replace" target="notifications-badge">',
       '<turbo-stream action="refresh">',
       '<turbo-stream action="replace" target="trip_recalculate_frame">']
    )
    expect(JSON.parse(published.first.last)).to include("id=\"navbar_notification_#{kept.id}\"")
    expect(JSON.parse(published.last.last)).to include('text-error')
    expect(published.map(&:last).join).not_to include("navbar_notification_#{lost.id}")
    expect(queued).to eq(0)
  ensure
    stop_rails_drainers(hooks, threads) if hooks
    capture&.kill
    cleanup!
    ActiveRecord::Base.connection.execute('DROP SCHEMA phoenix CASCADE') if created_schema
  end
end
